import XCTest
@testable import aruna

enum PortfolioTestError: Error {
    case remoteLoadFailed
    case upsertFailed
}

/// `PortfolioRepository` persistence behavior: local save/load, validation
/// filtering, sort + display-currency preference persistence, remote-first
/// load with local fallback, and local-first saves that survive remote failure.
@MainActor
final class PortfolioRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var storage: ArunaStorage!
    private var store: MockPortfolioRemoteStore!

    override func setUp() {
        super.setUp()
        suiteName = "PortfolioRepo-\(UUID().uuidString)"
        storage = ArunaStorage(defaults: UserDefaults(suiteName: suiteName)!)
        store = MockPortfolioRemoteStore()
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func repository(remote: MockPortfolioRemoteStore? = nil, override: PortfolioLoadOverride = .normal) -> PortfolioRepository {
        PortfolioRepository(storage: storage, remoteStore: remote, loadOverride: override)
    }

    private func holding(symbol: String, quantity: Double = 1, averagePrice: Double = 100) -> PortfolioHolding {
        PortfolioHolding(id: "\(symbol)_1", symbol: symbol, quantity: quantity, averagePrice: averagePrice)
    }

    // MARK: - Local persistence

    func testFreshStoreReturnsEmptyPortfolio() async throws {
        let holdings = try await repository().load()
        XCTAssertTrue(holdings.isEmpty)
    }

    func testLocalSaveLoadRoundTrip() async throws {
        let repo = repository()
        let date = ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        let original = [
            PortfolioHolding(id: "a", symbol: "NVDA", quantity: 10, averagePrice: 120, createdAt: date),
            PortfolioHolding(id: "b", symbol: "BBCA.JK", quantity: 2, averagePrice: 5_000, unit: "lot", createdAt: date),
        ]

        _ = try await repo.save(original)
        let loaded = try await repo.load()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.symbol), ["NVDA", "BBCA.JK"])
        XCTAssertEqual(loaded[0].quantity, 10)
        XCTAssertEqual(loaded[1].unit, "lot")
        XCTAssertEqual(loaded[0].createdAt, date)
    }

    func testSaveNormalizesSymbolOnDecode() async throws {
        let repo = repository()
        _ = try await repo.save([PortfolioHolding(id: "x", symbol: " nvda ", quantity: 1, averagePrice: 100)])

        let loaded = try await repo.load()
        XCTAssertEqual(loaded.map(\.symbol), ["NVDA"])
    }

    // MARK: - Validation filtering

    func testSaveDropsEmptySymbol() async throws {
        let saved = try await repository().save([
            holding(symbol: "NVDA"),
            PortfolioHolding(id: "empty", symbol: "", quantity: 1, averagePrice: 100),
        ])
        XCTAssertEqual(saved.map(\.symbol), ["NVDA"])
    }

    func testSaveDropsZeroAndNegativeQuantity() async throws {
        let saved = try await repository().save([
            PortfolioHolding(id: "z", symbol: "AAPL", quantity: 0, averagePrice: 100),
            PortfolioHolding(id: "n", symbol: "MSFT", quantity: -3, averagePrice: 100),
            holding(symbol: "NVDA"),
        ])
        XCTAssertEqual(saved.map(\.symbol), ["NVDA"])
    }

    func testSaveDropsNegativeAveragePrice() async throws {
        let saved = try await repository().save([
            PortfolioHolding(id: "neg", symbol: "AAPL", quantity: 1, averagePrice: -1),
            holding(symbol: "NVDA"),
        ])
        XCTAssertEqual(saved.map(\.symbol), ["NVDA"])
    }

    func testSaveAllowsZeroAveragePrice() async throws {
        let saved = try await repository().save([holding(symbol: "NVDA", averagePrice: 0)])
        XCTAssertEqual(saved.map(\.symbol), ["NVDA"])
    }

    // MARK: - Sort preference

    func testSortOptionDefaultsToSymbol() async {
        let repo = repository()
        let option = repo.loadSortOption()
        XCTAssertEqual(option, .symbol)
    }

    func testSortOptionPersists() async {
        let repo = repository()
        repo.saveSortOption(.profitLossAmount)
        XCTAssertEqual(repo.loadSortOption(), .profitLossAmount)
        XCTAssertEqual(storage.string(forKey: PortfolioRepository.sortKey), "profitLossAmount")
    }

    func testUnknownSortOptionFallsBackToSymbol() async {
        storage.set("bogus", forKey: PortfolioRepository.sortKey)
        XCTAssertEqual(repository().loadSortOption(), .symbol)
    }

    // MARK: - Display currency preference

    func testDisplayCurrencyDefaultsToIDR() async {
        XCTAssertEqual(repository().loadDisplayCurrency(), .idr)
    }

    func testDisplayCurrencyPersistsUppercased() async {
        let repo = repository()
        repo.saveDisplayCurrency(.usd)
        XCTAssertEqual(repo.loadDisplayCurrency(), .usd)
        XCTAssertEqual(storage.string(forKey: PortfolioRepository.currencyKey), "USD")
    }

    func testDisplayCurrencyReadsLowercasedStorage() async {
        storage.set("idr", forKey: PortfolioRepository.currencyKey)
        XCTAssertEqual(repository().loadDisplayCurrency(), .idr)
    }

    func testUnknownCurrencyFallsBackToIDR() async {
        storage.set("EUR", forKey: PortfolioRepository.currencyKey)
        XCTAssertEqual(repository().loadDisplayCurrency(), .idr)
    }

    // MARK: - Remote-first load

    func testRemoteSignedInLoadSucceedsAndCaches() async throws {
        store.entriesToReturn = [
            PortfolioHolding(id: "r1", symbol: "AAPL", quantity: 5, averagePrice: 200),
            PortfolioHolding(id: "r2", symbol: "NVDA", quantity: 3, averagePrice: 100),
        ]

        let holdings = try await repository(remote: store).load()

        XCTAssertEqual(holdings.map(\.symbol), ["AAPL", "NVDA"])
        let cached = try storage.jsonObject([PortfolioHolding].self, forKey: PortfolioRepository.localKey)
        XCTAssertEqual(cached?.map(\.symbol), ["AAPL", "NVDA"])
    }

    func testRemoteEmptyIsAValidValue() async throws {
        store.entriesToReturn = []
        let holdings = try await repository(remote: store).load()
        XCTAssertTrue(holdings.isEmpty)
    }

    func testRemoteFailureFallsBackToLocal() async throws {
        try storage.setJSON([holding(symbol: "TSLA")], forKey: PortfolioRepository.localKey)
        store.loadError = PortfolioTestError.remoteLoadFailed

        let holdings = try await repository(remote: store).load()

        XCTAssertEqual(holdings.map(\.symbol), ["TSLA"])
    }

    func testRemoteFailureMustNotDestroyLocalData() async throws {
        store.loadError = PortfolioTestError.remoteLoadFailed
        _ = try await repository(remote: store).save([holding(symbol: "NVDA")])
        store.loadError = nil

        let holdings = try await repository(remote: store).load()
        XCTAssertEqual(holdings.map(\.symbol), ["NVDA"])
    }

    // MARK: - Local-first save

    func testSaveUpsertsRemote() async throws {
        let repo = repository(remote: store)
        let saved = try await repo.save([holding(symbol: "NVDA")])
        XCTAssertEqual(store.upsertedEntries?.map(\.symbol), ["NVDA"])
        XCTAssertEqual(store.upsertCallCount, 1)
        XCTAssertEqual(saved.map(\.symbol), ["NVDA"])
    }

    func testSaveSurvivesRemoteUpsertFailure() async throws {
        store.upsertError = PortfolioTestError.upsertFailed
        let repo = repository(remote: store)

        let saved = try await repo.save([holding(symbol: "NVDA")])

        XCTAssertEqual(saved.map(\.symbol), ["NVDA"], "Remote failure must not roll back the mutation")
        let cached = try storage.jsonObject([PortfolioHolding].self, forKey: PortfolioRepository.localKey)
        XCTAssertEqual(cached?.map(\.symbol), ["NVDA"])
    }

    func testSaveDropsInvalidBeforeUpsert() async throws {
        let repo = repository(remote: store)
        _ = try await repo.save([
            holding(symbol: "NVDA"),
            PortfolioHolding(id: "bad", symbol: "", quantity: 1, averagePrice: 100),
        ])
        XCTAssertEqual(store.upsertedEntries?.map(\.symbol), ["NVDA"])
    }

    // MARK: - Overrides

    func testForceEmptyOverride() async throws {
        try storage.setJSON([holding(symbol: "NVDA")], forKey: PortfolioRepository.localKey)
        let holdings = try await repository(override: .forceEmpty).load()
        XCTAssertTrue(holdings.isEmpty)
    }

    func testForceFailureOverride() async {
        do {
            _ = try await repository(override: .forceFailure).load()
            XCTFail("forceFailure must throw")
        } catch {
            XCTAssertEqual(error as? PortfolioRepositoryError, .loadFailed)
        }
    }
}
