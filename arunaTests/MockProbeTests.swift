import XCTest
@testable import aruna

final class MockProbeTests: XCTestCase {
    func testMockMatchesRealBaseURL() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UITestURLProtocol.self]
        let session = URLSession(configuration: config)

        let client = APIClient(
            baseURL: URL(string: "https://aruna.rdyy.me/api")!,
            payloadKey: "test",
            session: session
        )
        let market = MarketRepository(apiClient: client)

        let quotes = try await market.fetchQuotes([" nvda ", "NVDA", "msft"])
        XCTAssertEqual(quotes.count, 2, "Mock must serve /api/quotes via path suffix match")
        XCTAssertEqual(quotes["NVDA"]?.name, "NVDA")
        XCTAssertEqual(quotes["MSFT"]?.price, 100)

        let results = try await market.searchSymbols("nvd")
        XCTAssertFalse(results.isEmpty, "Mock must serve /api/symbol-search via path suffix match")
        XCTAssertTrue(results.contains { $0.symbol == "NVD" })
    }
}
