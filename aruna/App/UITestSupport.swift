import Foundation

/// Deterministic offline API for UI tests. Enabled by the `-uitest-api-mock`
/// launch argument (routes the live `APIClient` through `UITestURLProtocol`).
/// Scenario switching uses the `UITEST_API_MODE` environment variable. This is
/// test support only — never reachable in normal launches.
enum UITestSupport {
    static var configuration: UITestConfiguration {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uitest-watchlist-empty") { return .watchlistEmpty }
        if arguments.contains("-uitest-watchlist-fail") { return .watchlistFail }
        if arguments.contains("-uitest-api-mock") { return .mockAPI }
        return .none
    }

    static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UITestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

enum UITestConfiguration: Equatable {
    case none
    case mockAPI
    case watchlistEmpty
    case watchlistFail

    var watchlistOverride: WatchlistLoadOverride {
        switch self {
        case .watchlistEmpty: return .forceEmpty
        case .watchlistFail: return .forceFailure
        case .none, .mockAPI: return .normal
        }
    }
}

/// API scenario injected via `UITEST_API_MODE`.
enum UITestAPIScenario: String {
    case standard
    case quotesFail = "quotes-fail"
    case quotesFailOnRefresh = "quotes-fail-on-refresh"
    case searchFail = "search-fail"
    case searchEmpty = "search-empty"
}

/// URLProtocol stub serving canned `/quotes` and `/symbol-search` responses.
/// `nonisolated` because URLSession calls it from a background queue while the
/// app target defaults to MainActor isolation.
final class UITestURLProtocol: URLProtocol {
    nonisolated private static let scenario = UITestAPIScenario(
        rawValue: ProcessInfo.processInfo.environment["UITEST_API_MODE"] ?? ""
    ) ?? .standard
    nonisolated(unsafe) private static var quotesRequestCount = 0

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        do {
            let (status, body) = try Self.response(for: request)
            NSLog("UITESTMOCK startLoading path=%@ status=%ld", request.url?.path ?? "nil", status)
            let url = request.url ?? URL(string: "https://uitest.local")!
            let http = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}

    nonisolated private static func response(for request: URLRequest) throws -> (Int, Data) {        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let query = request.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems ?? []
        NSLog("UITESTMOCK response method=%@ path=%@ url=%@", method, path, request.url?.absoluteString ?? "nil")

        switch (method, path) {
        case ("POST", let p) where p.hasSuffix("/quotes"):
            quotesRequestCount += 1
            if scenario == .quotesFail
                || (scenario == .quotesFailOnRefresh && quotesRequestCount > 1) {
                return (500, Data())
            }
            let body = try requestBody(request)
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let symbols = object?["symbols"] as? [String] ?? []
            var quotes: [String: Any] = [:]
            for symbol in symbols {
                quotes[symbol] = [
                    "symbol": symbol,
                    "name": symbol,
                    "price": 100,
                    "changePercent": 1.25,
                    "currency": "USD",
                ]
            }
            let payload = try JSONSerialization.data(withJSONObject: ["quotes": quotes])
            return (200, payload)
        case ("GET", let p) where p.hasSuffix("/symbol-search"):
            let queryText = query.first { $0.name == "q" }?.value ?? ""
            switch scenario {
            case .searchFail:
                return (500, Data())
            case .searchEmpty:
                return (200, Data(#"{"symbols":[]}"#.utf8))
            case .quotesFail, .quotesFailOnRefresh, .standard:
                if queryText.trimmingCharacters(in: .whitespaces).lowercased() == "zzz" {
                    return (200, Data(#"{"symbols":[]}"#.utf8))
                }
                let symbol = queryText.uppercased()
                let results: [[String: Any]] = [
                    ["symbol": symbol, "name": "\(symbol) Corp"],
                    ["symbol": "NVDA", "name": "NVIDIA Corp"],
                    ["symbol": "QQQ", "name": "Invesco QQQ"],
                ]
                let payload = try JSONSerialization.data(withJSONObject: ["symbols": results])
                return (200, payload)
            }
        default:
            return (200, Data("{}".utf8))
        }
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
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
        return Data()
    }
}
