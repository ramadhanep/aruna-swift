import XCTest
@testable import aruna

enum WatchlistTestError: Error {
    case remoteLoadFailed
    case upsertFailed
}

@MainActor
final class WatchlistRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var storage: ArunaStorage!
    private var store: MockWatchlistRemoteStore!

    override func setUp() {
        super.setUp()
        suiteName = "WatchlistRepo-\(UUID().uuidString)"
        storage = ArunaStorage(defaults: UserDefaults(suiteName: suiteName)!)
        store = MockWatchlistRemoteStore()
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func repository(remote: MockWatchlistRemoteStore? = nil) -> WatchlistRepository {
        WatchlistRepository(storage: storage, remoteStore: remote)
    }

    // 1. Empty local watchlist seeds defaults.
    func testEmptyLocalSeedsDefaults() async throws {
        let items = try await repository().load()
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(Set(items.map(\.symbol)), Set(WatchlistItem.defaultSymbols))
    }

    // 2. Seed order is exact.
    func testSeedOrderIsExact() async throws {
        let items = try await repository().load()
        XCTAssertEqual(
            items.map(\.symbol),
            ["BBCA.JK", "BBRI.JK", "BMRI.JK", "BTC-USD", "QQQ", "SPY", "NVDA", "MSFT"]
        )
        XCTAssertEqual(items.map(\.order), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    // 3. Existing local watchlist does not reseed.
    func testExistingLocalDoesNotReseed() async throws {
        let repo = repository()
        _ = try await repo.save([WatchlistItem(symbol: "AAPL")])

        let first = try await repo.load()
        XCTAssertEqual(first.map(\.symbol), ["AAPL"])

        let second = try await repo.load()
        XCTAssertEqual(second.map(\.symbol), ["AAPL"], "Seeded defaults must not overwrite existing data")
    }

    // 4. Duplicate symbols are deduplicated.
    func testDuplicateSymbolsAreDeduplicated() async throws {
        let items = try await repository().save([
            WatchlistItem(symbol: "NVDA"),
            WatchlistItem(symbol: "NVDA"),
            WatchlistItem(symbol: " nvda "),
        ])
        XCTAssertEqual(items.map(\.symbol), ["NVDA"])
    }

    // 5. Symbols normalize uppercase.
    func testSymbolsNormalizeUppercase() async throws {
        let items = try await repository().save([
            WatchlistItem(symbol: " bca "),
            WatchlistItem(symbol: "btc-usd"),
        ])
        XCTAssertEqual(items.map(\.symbol), ["BCA", "BTC-USD"])
    }

    // 6. Order fields are reindexed.
    func testOrderFieldsAreReindexed() async throws {
        let items = try await repository().save([
            WatchlistItem(symbol: "MSFT", order: 99),
            WatchlistItem(symbol: "NVDA", order: 1),
            WatchlistItem(symbol: "AAPL", order: 50),
        ])
        XCTAssertEqual(items.map(\.order), [1, 2, 3])
    }

    // 7. Local save round-trip.
    func testLocalSaveRoundTrip() async throws {
        let repo = repository()
        let date = ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        let original = [WatchlistItem(symbol: "BBCA.JK", name: "BCA", order: 1, addedAt: date)]

        _ = try await repo.save(original)
        let loaded = try await repo.load()

        XCTAssertEqual(loaded, original)
    }

    // 8. Date round-trip remains Flutter-compatible.
    func testDateRoundTripIsFlutterCompatible() async throws {
        let date = ArunaDate.isoParse("2026-08-09T12:00:00.123456")!
        _ = try await repository().save([WatchlistItem(symbol: "NVDA", addedAt: date)])

        let data = try XCTUnwrap(storage.defaults.data(forKey: WatchlistRepository.localKey))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(
            json.contains(#""addedAt":"2026-08-09T12:00:00.123456""#),
            "Dart toIso8601String format required, got: \(json)"
        )
        XCTAssertTrue(
            json.range(of: #"\.\d{6}""#, options: .regularExpression) != nil,
            "expected 6-digit fractional seconds: \(json)"
        )

        let decoded = try storage.jsonObject([WatchlistItem].self, forKey: WatchlistRepository.localKey)
        XCTAssertEqual(decoded, [WatchlistItem(symbol: "NVDA", order: 1, addedAt: date)])
    }

    // 9. Remote signed-in load succeeds.
    func testRemoteSignedInLoadSucceeds() async throws {
        store.itemsToReturn = [
            WatchlistItem(symbol: "AAPL", order: 1),
            WatchlistItem(symbol: "NVDA", order: 2),
        ]

        let items = try await repository(remote: store).load()

        XCTAssertEqual(items.map(\.symbol), ["AAPL", "NVDA"])
    }

    // 10. Remote load caches locally.
    func testRemoteLoadCachesLocally() async throws {
        store.itemsToReturn = [WatchlistItem(symbol: "AAPL")]

        _ = try await repository(remote: store).load()

        let cached = try storage.jsonObject([WatchlistItem].self, forKey: WatchlistRepository.localKey)
        XCTAssertEqual(cached?.map(\.symbol), ["AAPL"])
    }

    // 11. Remote failure falls back to local.
    func testRemoteFailureFallsBackToLocal() async throws {
        try storage.setJSON([WatchlistItem(symbol: "TSLA")], forKey: WatchlistRepository.localKey)
        store.loadError = WatchlistTestError.remoteLoadFailed

        let items = try await repository(remote: store).load()

        XCTAssertEqual(items.map(\.symbol), ["TSLA"])
    }

    // 12. Local mutation survives remote failure.
    func testLocalMutationSurvivesRemoteFailure() async throws {
        store.upsertError = WatchlistTestError.upsertFailed

        let items = try await repository(remote: store).save([WatchlistItem(symbol: "NVDA")])

        XCTAssertEqual(items.map(\.symbol), ["NVDA"], "Remote failure must not roll back the mutation")
        let cached = try storage.jsonObject([WatchlistItem].self, forKey: WatchlistRepository.localKey)
        XCTAssertEqual(cached?.map(\.symbol), ["NVDA"])
    }

    // 13. Add symbol.
    func testAddSymbol() async throws {
        let repo = repository(remote: store)
        let items = try await repo.save([WatchlistItem(symbol: "NVDA")])

        XCTAssertEqual(items.map(\.symbol), ["NVDA"])
        XCTAssertEqual(store.upsertedItems?.map(\.symbol), ["NVDA"])
        XCTAssertEqual(store.upsertCallCount, 1)
    }

    // 14. Add duplicate symbol.
    func testAddDuplicateSymbol() async throws {
        let repo = repository(remote: store)
        _ = try await repo.save([WatchlistItem(symbol: "NVDA"), WatchlistItem(symbol: "NVDA")])

        XCTAssertEqual(store.upsertedItems?.count, 1)
    }

    // 15. Remove symbol.
    func testRemoveSymbol() async throws {
        let repo = repository()
        _ = try await repo.save([WatchlistItem(symbol: "NVDA"), WatchlistItem(symbol: "MSFT")])

        let items = try await repo.save([WatchlistItem(symbol: "MSFT")])

        XCTAssertEqual(items.map(\.symbol), ["MSFT"])
        XCTAssertEqual(items.map(\.order), [1])
    }

    // 16. Reorder symbols (order reindexed, dedupe preserved).
    func testReorderSymbols() async throws {
        let repo = repository()
        _ = try await repo.save([WatchlistItem(symbol: "NVDA"), WatchlistItem(symbol: "MSFT"), WatchlistItem(symbol: "AAPL")])

        let items = try await repo.save([
            WatchlistItem(symbol: "AAPL"),
            WatchlistItem(symbol: "NVDA"),
            WatchlistItem(symbol: "MSFT"),
        ])

        XCTAssertEqual(items.map(\.symbol), ["AAPL", "NVDA", "MSFT"])
        XCTAssertEqual(items.map(\.order), [1, 2, 3])
    }

    // 17. Empty symbol input is rejected.
    func testEmptySymbolInputIsRejected() async throws {
        let items = try await repository().save([
            WatchlistItem(symbol: "   "),
            WatchlistItem(symbol: ""),
            WatchlistItem(symbol: "NVDA"),
        ])
        XCTAssertEqual(items.map(\.symbol), ["NVDA"])
    }
}
