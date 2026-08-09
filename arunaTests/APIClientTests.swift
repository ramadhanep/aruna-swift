import XCTest
@testable import aruna

@MainActor
final class APIClientTests: XCTestCase {
    private let payloadKey = "aruna-secret"

    private func client() -> APIClient {
        APIClient(
            baseURL: URL(string: "https://arunaa.vercel.app/api")!,
            payloadKey: payloadKey,
            session: mockSession()
        )
    }

    func testGet200JSON() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, #"{"status":"ok"}"#)
        }

        let value = try await client().get("/test")
        XCTAssertEqual((value as? [String: Any])?["status"] as? String, "ok")
    }

    func testPostSendsJSONBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )
            let body = try requestBodyData(request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["symbols"] as? [String], ["A", "B"])
            XCTAssertEqual(object["timeframe"] as? String, "1D")
            return try mockResponse(200, "{}")
        }

        _ = try await client().post("/quotes", body: ["symbols": ["A", "B"], "timeframe": "1D"])
    }

    func test200PayloadDecodes() async throws {
        let inner: [String: Any] = [
            "quotes": [
                "BBCA.JK": [
                    "symbol": "BBCA.JK",
                    "name": "Bank Central Asia",
                    "price": 10150,
                    "changePercent": 0.495,
                    "logo": "https://x/b.svg",
                ]
            ]
        ]
        let bodyString = String(data: try JSONSerialization.data(withJSONObject: inner), encoding: .utf8)!
        let encoded = xorEncodePayload(bodyString, key: payloadKey)
        let wrapper = String(
            data: try JSONSerialization.data(withJSONObject: ["payload": encoded]),
            encoding: .utf8
        )!

        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, wrapper)
        }

        let value = try await client().get("/quotes")
        let quotes = (value as? [String: Any])?["quotes"] as? [String: Any]
        let quoteJSON = try XCTUnwrap(quotes?["BBCA.JK"] as? [String: Any])
        let quote = StockQuote(json: quoteJSON)
        XCTAssertEqual(quote.symbol, "BBCA.JK")
        XCTAssertEqual(quote.name, "Bank Central Asia")
        XCTAssertEqual(quote.price, 10150)
        XCTAssertEqual(quote.changePercent, 0.495)
        XCTAssertEqual(quote.logoURL, "https://x/b.svg")
    }

    func test204EmptyBodyIsValid() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(204, "")
        }

        let value = try await client().get("/test")
        XCTAssertNil(value)
    }

    func testNon2xxWithErrorField() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(400, #"{"error":"Bad request"}"#)
        }

        do {
            _ = try await client().get("/test")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertEqual(error.message, "Bad request")
        }
    }

    func testNon2xxWithoutErrorField() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(500, #"{"detail":"boom"}"#)
        }

        do {
            _ = try await client().get("/test")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 500)
            XCTAssertEqual(error.message, "Request failed.")
        }
    }

    func testInvalidJSON() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, "not json")
        }

        do {
            _ = try await client().get("/test")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Server returned a non-JSON response.")
        }
    }

    func testInvalidPayload() async throws {
        MockURLProtocol.requestHandler = { _ in
            try mockResponse(200, #"{"payload":"!!!"}"#)
        }

        do {
            _ = try await client().get("/test")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Unable to decode the API payload. Check ARUNA_SECURE_PAYLOAD_KEY.")
        }
    }
}
