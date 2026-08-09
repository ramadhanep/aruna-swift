import XCTest
@testable import aruna

final class SecurePayloadTests: XCTestCase {
    private let validKey = "testkey"
    private let validPayload = "D0cbEQcJFlZfUQMEFxUQRw4=" // {"hello":"world"}
    private let quotesKey = "aruna-secret"
    private let quotesPayload = "GlAEGw5ZFhZBSEUPQzA3LSADOS5BSEUPQwEMAwNCH0dZUkc2IzE0QCtmUUlDUAsVDBdXVEEPMQQNGUU3BBwBHABBUyQQGwRWTVJXHhNEEABBSEVFUUNAXk0NUQYLEwsTBFBPTlQdX0VBEQ0VDxUQPgRfEAANBkdOQUJbWlgYX0VBHgoTDlBPTkNFBxETAV9bTgpaDANOXRYVFUcJHA8="

    @MainActor
    func testValidPayloadDecodes() throws {
        let decoded = SecurePayload.decode(validPayload, key: validKey) as? [String: Any]
        XCTAssertEqual(decoded?["hello"] as? String, "world")
    }

    @MainActor
    func testQuotesVectorDecodes() throws {
        let decoded = SecurePayload.decode(quotesPayload, key: quotesKey) as? [String: Any]
        let quotes = decoded?["quotes"] as? [String: Any]
        let bca = quotes?["BBCA.JK"] as? [String: Any]
        XCTAssertEqual(bca?["name"] as? String, "Bank Central Asia")
        XCTAssertEqual(bca?["price"] as? Double, 10150)
    }

    @MainActor
    func testWrongKeyFails() throws {
        XCTAssertNil(SecurePayload.decode(validPayload, key: "wrong-key"))
    }

    @MainActor
    func testInvalidBase64Fails() throws {
        XCTAssertNil(SecurePayload.decode("!!!not-base64!!!", key: validKey))
        XCTAssertNil(SecurePayload.decode("a", key: validKey))
        XCTAssertNil(SecurePayload.decode("AB C", key: validKey))
    }

    @MainActor
    func testInvalidJSONFails() throws {
        // Valid base64 + key, but the plaintext is not JSON.
        let payload = xorEncodePayload("not json here", key: validKey)
        XCTAssertNil(SecurePayload.decode(payload, key: validKey))
    }

    @MainActor
    func testEmptyPayloadFails() throws {
        XCTAssertNil(SecurePayload.decode("", key: validKey))
        XCTAssertNil(SecurePayload.decode("AAAA", key: ""))
    }
}
