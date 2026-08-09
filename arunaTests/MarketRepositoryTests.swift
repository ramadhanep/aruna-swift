import XCTest
@testable import aruna

@MainActor
final class MarketRepositoryTests: XCTestCase {
    private func repository() -> MarketRepository {
        MarketRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://arunaa.vercel.app/api")!,
                payloadKey: "aruna-secret",
                session: mockSession()
            )
        )
    }

    func testFetchQuotesDedupesAndUppercases() async throws {
        var sentSymbols: [String]?
        MockURLProtocol.requestHandler = { request in
            let body = try requestBodyData(request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            sentSymbols = object["symbols"] as? [String]
            XCTAssertEqual(object["timeframe"] as? String, "1D")

            let quotes: [String: Any] = [
                "BBC.JK": ["symbol": "bbc.jk", "name": "BCA", "price": 10150],
                "NVDA": ["symbol": "nvda", "name": "NVIDIA", "price": "120.5"],
            ]
            let wrapper = String(
                data: try JSONSerialization.data(withJSONObject: ["quotes": quotes]),
                encoding: .utf8
            )!
            return try mockResponse(200, wrapper)
        }

        let result = try await repository().fetchQuotes(["bbc.jk", "BBC.JK", " NVDA "])

        XCTAssertEqual(sentSymbols, ["BBC.JK", "NVDA"])
        XCTAssertEqual(Set(result.keys), ["BBC.JK", "NVDA"])
        XCTAssertEqual(result["BBC.JK"]?.name, "BCA")
        XCTAssertEqual(result["NVDA"]?.price, 120.5)
    }

    func testFetchQuotesEmptySymbolsSkipsNetwork() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Network should not be called for empty symbols")
            return try mockResponse(500, "")
        }

        let result = try await repository().fetchQuotes(["  ", ""])
        XCTAssertTrue(result.isEmpty)
    }

    func testSearchSymbols() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "aapl")
            return try mockResponse(200, #"{"symbols":[{"symbol":"aapl","longname":"Apple"}]}"#)
        }

        let results = try await repository().searchSymbols("  aapl ")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].symbol, "AAPL")
        XCTAssertEqual(results[0].name, "Apple")
    }

    func testSearchSymbolsEmptyQueryReturnsEmpty() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Network should not be called for empty query")
            return try mockResponse(500, "")
        }
        let results = try await repository().searchSymbols("   ")
        XCTAssertTrue(results.isEmpty)
    }

    func testFetchPriceSeriesFiltersNonPositive() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let symbol = components.queryItems?.first(where: { $0.name == "symbol" })?.value
            XCTAssertEqual(symbol, "NVDA")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "timeframe" })?.value, "D")
            return try mockResponse(200, #"{"data":[{"date":"2026-08-09","price":10},{"date":"2026-08-10","price":0},{"date":"2026-08-11","close":"12.5"}]}"#)
        }

        let points = try await repository().fetchPriceSeries("nvda")
        XCTAssertEqual(points.map(\.price), [10, 12.5])
    }

    func testFetchLatestFinancePriceScansReversed() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let symbol = components.queryItems?.first(where: { $0.name == "symbol" })?.value
            XCTAssertEqual(symbol, "IDR=X")
            XCTAssertNotNil(components.queryItems?.first(where: { $0.name == "endDate" }))
            XCTAssertNotNil(components.queryItems?.first(where: { $0.name == "startDate" }))
            return try mockResponse(200, #"{"data":[{"adjclose":3,"close":4},{"close":0},{"adjclose":"15.5"}]}"#)
        }

        // Rows are scanned in reverse: the last row wins.
        let price = try await repository().fetchLatestFinancePrice("IDR=X")
        XCTAssertEqual(price, 15.5)
    }

    func testFetchLatestFinancePriceNoRowsReturnsNil() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, #"{"data":[{"close":0},{"price":0}]}"#)
        }
        let price = try await repository().fetchLatestFinancePrice("SGD=X")
        XCTAssertNil(price)
    }

    func testFetchFundamentalsReturnsNilForNonMap() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, "[]")
        }
        let summary = try await repository().fetchFundamentals("NVDA")
        XCTAssertNil(summary)
    }
}
