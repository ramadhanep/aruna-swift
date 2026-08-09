import XCTest
@testable import aruna

@MainActor
final class WatchlistViewModelTests: XCTestCase {
    private var suiteName: String!
    private var storage: ArunaStorage!

    override func setUp() {
        super.setUp()
        suiteName = "WatchlistVM-\(UUID().uuidString)"
        storage = ArunaStorage(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeViewModel(
        remoteStore: MockWatchlistRemoteStore? = nil,
        loadOverride: WatchlistLoadOverride = .normal
    ) -> WatchlistViewModel {
        let repository = WatchlistRepository(storage: storage, remoteStore: remoteStore, loadOverride: loadOverride)
        let market = MarketRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://example.com")!,
                payloadKey: "test",
                session: mockSession()
            )
        )
        return WatchlistViewModel(repository: repository, market: market)
    }

    private static let quotesOK = #"{"quotes":{"NVDA":{"symbol":"NVDA","name":"NVIDIA","price":120,"changePercent":1.5}}}"#

    // Initial load: loading → loaded with seeded symbols + quotes.
    func testInitialLoadLoadingToLoaded() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, Self.quotesOK)
        }
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.phase, .loading)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.items.map(\.symbol), WatchlistItem.defaultSymbols)
        XCTAssertEqual(viewModel.quotes["NVDA"]?.name, "NVIDIA")
        XCTAssertNil(viewModel.quoteError)
    }

    // Initial load with quote failure → loaded symbols + quote warning.
    func testInitialLoadQuoteFailureShowsWarning() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(500, #"{"error":"quotes down"}"#)
        }
        let viewModel = makeViewModel()

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.items.map(\.symbol), WatchlistItem.defaultSymbols)
        XCTAssertTrue(viewModel.quotes.isEmpty)
        XCTAssertNotNil(viewModel.quoteError)
    }

    // Refresh success clears the warning and loads quotes.
    func testRefreshSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(500, #"{"error":"quotes down"}"#)
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertNotNil(viewModel.quoteError)

        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, Self.quotesOK)
        }
        await viewModel.refreshQuotes()

        XCTAssertNil(viewModel.quoteError)
        XCTAssertEqual(viewModel.quotes["NVDA"]?.price, 120)
    }

    // Refresh failure keeps the persisted symbols (and previously loaded quotes).
    func testRefreshFailureKeepsExistingSymbols() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, Self.quotesOK)
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        let itemsBefore = viewModel.items

        MockURLProtocol.requestHandler = { _ in
            try mockResponse(500, "")
        }
        await viewModel.refreshQuotes()

        XCTAssertEqual(viewModel.items, itemsBefore)
        XCTAssertNotNil(viewModel.quoteError)
        XCTAssertEqual(viewModel.quotes["NVDA"]?.price, 120, "Flutter keeps stale quotes on refresh failure")
    }

    // Add success prepends the symbol and refreshes.
    func testAddSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, #"{"quotes":{}}"#)
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        let added = try await viewModel.addSymbol("TSLA")

        XCTAssertTrue(added)
        XCTAssertEqual(viewModel.items.first?.symbol, "TSLA")
        XCTAssertEqual(viewModel.items.count, 9)
    }

    // Duplicate add is a no-op preserving the existing item/order.
    func testDuplicateAddIsNoOp() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, #"{"quotes":{}}"#)
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        _ = try await viewModel.addSymbol("TSLA")
        let before = viewModel.items

        let added = try await viewModel.addSymbol("TSLA")

        XCTAssertFalse(added)
        XCTAssertEqual(viewModel.items, before)
        XCTAssertEqual(viewModel.items.filter { $0.symbol == "TSLA" }.count, 1)
    }

    // Delete success removes the row and reindexes.
    func testDeleteSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, Self.quotesOK)
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        try await viewModel.removeSymbol("NVDA")

        XCTAssertFalse(viewModel.items.contains { $0.symbol == "NVDA" })
        XCTAssertEqual(viewModel.items.count, 7)
        XCTAssertEqual(viewModel.items.map(\.order), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertNil(viewModel.quotes["NVDA"])
    }

    // Reorder persists the new order with reindexed order fields.
    func testReorder() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, Self.quotesOK)
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        await viewModel.reorderSymbol(from: "NVDA", to: "MSFT")

        XCTAssertEqual(viewModel.items.last?.symbol, "NVDA")
        let persisted = try storage.jsonObject([WatchlistItem].self, forKey: WatchlistRepository.localKey)
        XCTAssertEqual(persisted?.map(\.order), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    // Repository failure → failed state (never an infinite loading).
    func testRepositoryFailureEntersFailedState() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Quotes should not be requested when the repository fails")
            return try mockResponse(500, "")
        }
        let viewModel = makeViewModel(loadOverride: .forceFailure)

        await viewModel.load()

        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("Expected .failed, got \(viewModel.phase)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // Watchlist → MarketRepository: POST /quotes with normalized, deduped symbols + timeframe 1D.
    func testQuotesRequestNormalizedWithTimeframe1D() async throws {
        var receivedSymbols: [String]?
        var receivedTimeframe: String?
        MockURLProtocol.requestHandler = { request in
            let body = try requestBodyData(request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            receivedSymbols = object["symbols"] as? [String]
            receivedTimeframe = object["timeframe"] as? String
            return try mockResponse(200, #"{"quotes":{}}"#)
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(receivedTimeframe, "1D")
        XCTAssertEqual(receivedSymbols, WatchlistItem.defaultSymbols)
    }

    // Empty watchlist must not fire a quote request.
    func testEmptySymbolsSendNoQuoteRequest() async throws {
        var called = false
        MockURLProtocol.requestHandler = { _ in
            called = true
            return try mockResponse(200, #"{"quotes":{}}"#)
        }
        let viewModel = makeViewModel(loadOverride: .forceEmpty)

        await viewModel.load()

        XCTAssertFalse(called, "No symbols means no unnecessary /quotes request")
        XCTAssertEqual(viewModel.items, [])
    }
}
