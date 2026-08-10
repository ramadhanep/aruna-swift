import XCTest
@testable import aruna

/// Portfolio math + controller behavior: shares, lots ×100, cash, FX (IDR/SGD)
/// with USD fallback, summary, distributions, sorting, `positionFor`
/// aggregation, and add/update/remove flows. All market data is served through
/// `MockURLProtocol` — no network, no credentials.
@MainActor
final class PortfolioViewModelTests: XCTestCase {
    private var suiteName: String!
    private var storage: ArunaStorage!

    override func setUp() {
        super.setUp()
        suiteName = "PortfolioVM-\(UUID().uuidString)"
        storage = ArunaStorage(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Market doubles

    private func makeMarket(
        financePrices: [String: Double] = ["IDR=X": 16_000, "SGD=X": 1.35],
        quotePrices: [String: Double] = [:]
    ) -> MarketRepository {
        let session = mockSession()
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(string: "https://example.com/api")!
            let path = url.path
            if path.hasSuffix("/finance") {
                let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "symbol" }?.value ?? ""
                if let price = financePrices[symbol] {
                    return try Self.respond(200, ["data": [["adjclose": price]]])
                }
                return try Self.respond(200, ["data": []])
            }
            if path.hasSuffix("/quotes") {
                let body = try requestBodyData(request)
                let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                let symbols = object?["symbols"] as? [String] ?? []
                var map: [String: Any] = [:]
                for symbol in symbols {
                    map[symbol] = [
                        "symbol": symbol,
                        "name": symbol,
                        "price": quotePrices[symbol] ?? 100,
                        "changePercent": 1.25,
                        "currency": "USD",
                    ]
                }
                return try Self.respond(200, ["quotes": map])
            }
            return try Self.respond(200, [:])
        }
        return MarketRepository(apiClient: APIClient(
            baseURL: URL(string: "https://example.com/api")!,
            payloadKey: "test",
            session: session
        ))
    }

    private static func respond(_ status: Int, _ object: [String: Any]) throws -> (HTTPURLResponse, Data) {
        let payload = try JSONSerialization.data(withJSONObject: object)
        let http = HTTPURLResponse(
            url: URL(string: "https://example.com/api")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (http, payload)
    }

    // MARK: - Helpers

    private func makeViewModel(market: MarketRepository) -> PortfolioViewModel {
        let repo = PortfolioRepository(storage: storage, remoteStore: nil)
        return PortfolioViewModel(repository: repo, market: market)
    }

    private func seed(_ holdings: [PortfolioHolding]) async throws {
        _ = try await PortfolioRepository(storage: storage).save(holdings)
    }

    private func digital(symbol: String, quantity: Double, averagePrice: Double, unit: String = "share") -> PortfolioHolding {
        PortfolioHolding(
            id: "\(symbol)_1", symbol: symbol, quantity: quantity, averagePrice: averagePrice,
            unit: unit, assetType: symbol.hasSuffix("-USD") ? "crypto" : "stock"
        )
    }

    // MARK: - Shares (USD, IDR display)

    func testShareMetricsInIDR() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        let position = try XCTUnwrap(state.digitalPositions.first)
        XCTAssertEqual(position.currentValueUSD, 1_000, accuracy: 0.0001)
        XCTAssertEqual(position.costBasisUSD, 1_000, accuracy: 0.0001)
        XCTAssertEqual(position.profitLoss, 0, accuracy: 0.0001)
        XCTAssertEqual(position.displayQuantity, 10)
        XCTAssertEqual(position.currency, "IDR")
        XCTAssertEqual(state.effectiveCurrency, .idr)
        XCTAssertEqual(state.summary.totalValue, 16_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.totalCost, 16_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.profitLoss, 0, accuracy: 0.0001)
    }

    func testShareProfitAndLoss() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket(quotePrices: ["NVDA": 120]))
        await vm.load()

        let position = try XCTUnwrap(vm.state?.digitalPositions.first)
        XCTAssertEqual(position.currentValueUSD, 1_200, accuracy: 0.0001)
        XCTAssertEqual(position.profitLoss, 3_200_000, accuracy: 0.0001, "120*10*16000 - 100*10*16000")
        XCTAssertEqual(position.profitLossPercent, 20, accuracy: 0.0001)
    }

    // MARK: - Lots ×100

    func testLotMetricsMultiplyBy100() async throws {
        try await seed([digital(symbol: "BBCA.JK", quantity: 2, averagePrice: 5_000, unit: "lot")])
        let vm = makeViewModel(market: makeMarket(quotePrices: ["BBCA.JK": 15_000]))
        await vm.load()

        let position = try XCTUnwrap(vm.state?.digitalPositions.first)
        XCTAssertEqual(position.holding.effectiveQuantity, 200)
        XCTAssertEqual(position.displayQuantity, 200)
        // .JK native price converted to USD via IDR rate, then back to IDR.
        XCTAssertEqual(position.currentValueUSD, (15_000.0 / 16_000.0) * 200, accuracy: 0.0001)
        XCTAssertEqual(position.costBasisUSD, (5_000.0 / 16_000.0) * 200, accuracy: 0.0001)
        XCTAssertEqual(position.currentValue, 3_000_000, accuracy: 0.0001)
        XCTAssertEqual(position.costBasis, 1_000_000, accuracy: 0.0001)
        XCTAssertEqual(position.profitLoss, 2_000_000, accuracy: 0.0001)
        XCTAssertEqual(position.profitLossPercent, 200, accuracy: 0.0001)
    }

    // MARK: - Cash

    func testAddCashHoldingInIDR() async throws {
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        try await vm.addHolding(symbol: "", quantity: 1_000_000, averagePrice: 0, type: "cash", category: "Emergency", cashCurrency: "IDR", nativeAmount: 1_000_000, emoji: "💰")

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.holdings.count, 1)
        let cash = state.holdings[0]
        XCTAssertEqual(cash.symbol, "CASH_IDR")
        XCTAssertEqual(cash.cashCurrency, "IDR")
        XCTAssertEqual(cash.nativeAmount, 1_000_000)
        XCTAssertEqual(cash.averagePrice, 1_000_000.0 / 16_000.0, accuracy: 0.0001)
        XCTAssertEqual(cash.quantity, 1)
        XCTAssertEqual(cash.category, "Emergency")

        let position = try XCTUnwrap(state.cashPositions.first)
        XCTAssertEqual(position.currentValue, 1_000_000, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(position.nativeCashValue), 1_000_000, accuracy: 0.0001)
        XCTAssertEqual(position.profitLoss, 0)
        XCTAssertEqual(position.displayQuantity, 1_000_000)
        XCTAssertEqual(state.summary.cashValue, 1_000_000, accuracy: 0.0001)
    }

    func testAddCashHoldingWithoutFXIsRejected() async throws {
        let vm = makeViewModel(market: makeMarket(financePrices: [:]))
        await vm.load()

        try await vm.addHolding(symbol: "", quantity: 1_000_000, averagePrice: 0, type: "cash", category: "Emergency", cashCurrency: "IDR", nativeAmount: 1_000_000)

        XCTAssertTrue(vm.state?.holdings.isEmpty == true, "IDR cash add must no-op when IDR FX is unavailable")
        XCTAssertTrue(vm.state?.fxError?.contains("IDR FX unavailable") == true)
    }

    func testCashUSDFallbackWhenDisplayIDRUnavailable() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket(financePrices: [:]))
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.effectiveCurrency, .usd)
        XCTAssertEqual(state.summary.currency, .usd)
        XCTAssertEqual(state.summary.totalValue, 1_000, accuracy: 0.0001)
        XCTAssertTrue(state.fxError?.contains("IDR FX unavailable") == true)
        XCTAssertTrue(state.fxError?.contains("SGD FX unavailable") == true)
    }

    // MARK: - SGD display

    func testSGDDisplayConversion() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        await vm.setDisplayCurrency(.sgd)

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.effectiveCurrency, .sgd)
        XCTAssertEqual(state.summary.currency, .sgd)
        XCTAssertEqual(state.summary.totalValue, 1_350, accuracy: 0.0001, "1000 USD * 1.35")
        XCTAssertEqual(state.digitalPositions.first?.currency, "SGD")
    }

    // MARK: - Zero-cost P/L

    func testProfitLossPercentIsZeroWhenCostIsZero() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 0)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let position = try XCTUnwrap(vm.state?.digitalPositions.first)
        XCTAssertEqual(position.profitLossPercent, 0)
        XCTAssertEqual(vm.state?.summary.profitLossPercent, 0, "0-cost portfolio must not divide by zero")
    }

    // MARK: - Summary totals

    func testSummaryTotalsDigitalAndCash() async throws {
        try await seed([
            digital(symbol: "NVDA", quantity: 10, averagePrice: 100),
            PortfolioHolding(id: "c", symbol: "CASH_USD", quantity: 1, averagePrice: 500, type: "cash", unit: "unit", cashCurrency: "USD", nativeAmount: 500),
        ])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.summary.digitalValue, 16_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.cashValue, 8_000_000, accuracy: 0.0001, "500 USD * 16000")
        XCTAssertEqual(state.summary.totalValue, 24_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.digitalCost, 16_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.totalCost, 24_000_000, accuracy: 0.0001)
        XCTAssertEqual(state.summary.profitLoss, 0, accuracy: 0.0001)
    }

    // MARK: - Distributions

    func testAssetTypeDistribution() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.assetTypeDistribution.count, 1, "cash slice omitted when cash value is 0")
        XCTAssertEqual(state.assetTypeDistribution[0].label, "Digital Assets")
        XCTAssertEqual(state.assetTypeDistribution[0].value, 16_000_000, accuracy: 0.0001)
    }

    func testCashDistributionGroupsByCurrency() async throws {
        try await seed([
            PortfolioHolding(id: "c1", symbol: "CASH_IDR", quantity: 1, averagePrice: 62.5, type: "cash", unit: "unit", cashCurrency: "IDR", nativeAmount: 1_000_000),
            PortfolioHolding(id: "c2", symbol: "CASH_USD", quantity: 1, averagePrice: 200, type: "cash", unit: "unit", cashCurrency: "USD", nativeAmount: 200),
        ])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        let byLabel = Dictionary(uniqueKeysWithValues: state.cashDistribution.map { ($0.label, $0.valueUSD) })
        XCTAssertEqual(try XCTUnwrap(byLabel["IDR"]), 62.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(byLabel["USD"]), 200, accuracy: 0.0001)
    }

    func testHoldingsDistributionUsesDisplayName() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.holdingsDistribution.map(\.label), ["NVDA"])
        XCTAssertEqual(state.digitalDistribution.map(\.label), ["NVDA"])
    }

    // MARK: - Sorting

    func testSortBySymbol() async throws {
        try await seed([
            digital(symbol: "MSFT", quantity: 1, averagePrice: 100),
            digital(symbol: "AAPL", quantity: 1, averagePrice: 100),
            digital(symbol: "NVDA", quantity: 1, averagePrice: 100),
        ])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        XCTAssertEqual(vm.state?.digitalPositions.map(\.holding.symbol), ["AAPL", "MSFT", "NVDA"])
    }

    func testSortByCurrentValueDescending() async throws {
        try await seed([
            digital(symbol: "MSFT", quantity: 1, averagePrice: 100),
            digital(symbol: "NVDA", quantity: 10, averagePrice: 100),
            digital(symbol: "AAPL", quantity: 5, averagePrice: 100),
        ])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        await vm.setSortOption(.currentValue)

        XCTAssertEqual(vm.state?.digitalPositions.map(\.holding.symbol), ["NVDA", "AAPL", "MSFT"])
        XCTAssertEqual(storage.string(forKey: PortfolioRepository.sortKey), "currentValue")
    }

    func testSortProfitLossPercentDescendingWithSymbolTiebreak() async throws {
        try await seed([
            digital(symbol: "MSFT", quantity: 1, averagePrice: 100),
            digital(symbol: "NVDA", quantity: 1, averagePrice: 100),
            digital(symbol: "AAPL", quantity: 1, averagePrice: 50),
        ])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        await vm.setSortOption(.profitLossPercent)

        // AAPL +100% (cost 50, value 100) ranks first; NVDA/MSFT tie at 0% → symbol order.
        XCTAssertEqual(vm.state?.digitalPositions.map(\.holding.symbol), ["AAPL", "MSFT", "NVDA"])
    }

    // MARK: - positionFor aggregation

    func testPositionForAggregatesDuplicateHoldings() async throws {
        let first = digital(symbol: "NVDA", quantity: 10, averagePrice: 100)
        let second = PortfolioHolding(
            id: "NVDA_2", symbol: "NVDA", quantity: 5, averagePrice: 200, assetType: "stock"
        )
        try await seed([first, second])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        let context = try XCTUnwrap(vm.positionFor(" nvda "))
        XCTAssertEqual(context.symbol, "NVDA")
        XCTAssertEqual(context.quantity, 15)
        XCTAssertEqual(context.costBasis, 16_000_000 + 16_000_000, accuracy: 0.0001, "(100*10 + 200*5)*16000")
        XCTAssertEqual(context.currentValue, 24_000_000, accuracy: 0.0001, "(100*10 + 100*5)*16000")
        XCTAssertEqual(context.unrealizedGain, -8_000_000, accuracy: 0.0001)
        XCTAssertEqual(context.averageCost, 32_000_000.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(context.unrealizedGainPercent, -25, accuracy: 0.1, "(-8M / 32M) * 100")
        XCTAssertEqual(context.currency, "IDR")
    }

    func testPositionForUnknownSymbolReturnsNil() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        XCTAssertNil(vm.positionFor("MSFT"))
    }

    // MARK: - Mutations

    func testAddHoldingPersistsAndReloads() async throws {
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        try await vm.addHolding(symbol: "nvda", quantity: 10, averagePrice: 100, currency: "usd", market: "us", assetType: "stock")

        let state = try XCTUnwrap(vm.state)
        let holding = try XCTUnwrap(state.holdings.first)
        XCTAssertEqual(holding.symbol, "NVDA")
        XCTAssertEqual(holding.unit, "share")
        XCTAssertEqual(holding.assetType, "stock")
        XCTAssertEqual(holding.currency, "USD")
        XCTAssertEqual(holding.market, "US")

        let reloaded = makeViewModel(market: makeMarket())
        await reloaded.load()
        XCTAssertEqual(reloaded.state?.holdings.map(\.symbol), ["NVDA"])
    }

    func testUpdateHoldingPreservesId() async throws {
        let vm = makeViewModel(market: makeMarket())
        await vm.load()
        try await vm.addHolding(symbol: "NVDA", quantity: 10, averagePrice: 100)
        let id = try XCTUnwrap(vm.state?.holdings.first?.id)

        try await vm.updateHolding(id: id, symbol: "NVDA", quantity: 20, averagePrice: 150)

        let state = try XCTUnwrap(vm.state)
        XCTAssertEqual(state.holdings.count, 1)
        XCTAssertEqual(state.holdings[0].id, id)
        XCTAssertEqual(state.holdings[0].quantity, 20)
        XCTAssertEqual(state.holdings[0].averagePrice, 150)
    }

    func testRemoveHolding() async throws {
        let vm = makeViewModel(market: makeMarket())
        await vm.load()
        try await vm.addHolding(symbol: "NVDA", quantity: 10, averagePrice: 100)
        try await vm.addHolding(symbol: "AAPL", quantity: 5, averagePrice: 200)
        let nvdaID = try XCTUnwrap(vm.state?.holdings.first { $0.symbol == "NVDA" }?.id)

        try await vm.removeHolding(id: nvdaID)

        XCTAssertEqual(vm.state?.holdings.map(\.symbol), ["AAPL"])
        let reloaded = makeViewModel(market: makeMarket())
        await reloaded.load()
        XCTAssertEqual(reloaded.state?.holdings.map(\.symbol), ["AAPL"])
    }

    // MARK: - Preferences

    func testSetDisplayCurrencyPersists() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()

        await vm.setDisplayCurrency(.usd)

        XCTAssertEqual(storage.string(forKey: PortfolioRepository.currencyKey), "USD")
        XCTAssertEqual(vm.state?.displayCurrency, .usd)
        XCTAssertEqual(vm.state?.effectiveCurrency, .usd)
        XCTAssertEqual(try XCTUnwrap(vm.state?.summary.totalValue), 1_000, accuracy: 0.0001)
    }

    // MARK: - Refresh

    func testRefreshKeepsHoldingsAndWarnsOnQuoteFailure() async throws {
        try await seed([digital(symbol: "NVDA", quantity: 10, averagePrice: 100)])
        let vm = makeViewModel(market: makeMarket())
        await vm.load()
        XCTAssertNil(vm.state?.quoteError)

        // Swap the market's quote response to a failure, then reload through a
        // vm whose market fails: holdings must survive + a warning surfaces.
        let session = mockSession()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/finance") == true {
                return try Self.respond(200, ["data": [["adjclose": 16_000]]])
            }
            throw URLError(.badServerResponse)
        }
        let failingMarket = MarketRepository(apiClient: APIClient(
            baseURL: URL(string: "https://example.com/api")!, payloadKey: "test", session: session
        ))
        let vm2 = PortfolioViewModel(repository: PortfolioRepository(storage: storage, remoteStore: nil), market: failingMarket)
        await vm2.load()
        XCTAssertEqual(vm2.state?.holdings.map(\.symbol), ["NVDA"])
        XCTAssertNotNil(vm2.state?.quoteError, "Holdings survive a quote failure and a warning is surfaced")
    }
}
