import Foundation

/// URLProtocol stub for deterministic, offline networking tests.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (httpResponse, data) = try handler(request)
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Ephemeral URLSession routed through `MockURLProtocol`.
func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Builds a response for the mock.
func mockResponse(_ status: Int, _ body: String) throws -> (HTTPURLResponse, Data) {
    let url = URL(string: "https://arunaa.vercel.app/api/test")!
    let http = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    return (http, Data(body.utf8))
}

/// Test-only encoder producing the same XOR+base64 payload format as the API.
func xorEncodePayload(_ text: String, key: String) -> String {
    let keyBytes = Array(key.utf8)
    let out = Array(text.utf8).enumerated().map { index, byte in
        byte ^ keyBytes[index % keyBytes.count]
    }
    return Data(out).base64EncodedString()
}

/// URLSession converts `httpBody` to `httpBodyStream` before handing the
/// request to URLProtocol, so read whichever one is populated.
func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
    throw NSError(
        domain: "ArunaTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Request has no body"]
    )
}
