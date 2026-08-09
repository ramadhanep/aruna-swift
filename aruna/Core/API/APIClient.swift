import Foundation

protocol APIClientProtocol: Sendable {
    func get(_ path: String, query: [String: String?]) async throws -> Any?
    func post(_ path: String, body: [String: Any]) async throws -> Any?
}

/// Port of Flutter `ApiClient` (`lib/core/api/api_client.dart`).
///
/// URLSession + async/await. No third-party HTTP library. Market endpoints
/// never receive an Authorization header.
struct APIClient: APIClientProtocol {
    let baseURL: URL
    let securePayloadKey: String
    let session: URLSession

    init(baseURL: URL, payloadKey: String, session: URLSession = .shared) {
        self.baseURL = Self.normalized(baseURL)
        self.securePayloadKey = payloadKey
        self.session = session
    }

    func get(_ path: String, query: [String: String?] = [:]) async throws -> Any? {
        var url = endpoint(path)
        let clean = query.compactMapValues { $0 }.filter { !$0.value.isEmpty }
        if !clean.isEmpty {
            url.append(queryItems: clean.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        let (data, response) = try await session.data(from: url)
        return try decode(response: response, data: data)
    }

    func post(_ path: String, body: [String: Any] = [:]) async throws -> Any? {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        return try decode(response: response, data: data)
    }

    // MARK: - Private

    private static func normalized(_ url: URL) -> URL {
        var value = url.absoluteString
        if value.hasSuffix("/") {
            value = String(value.dropLast())
        }
        return URL(string: value) ?? url
    }

    private func endpoint(_ path: String) -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func decode(response: URLResponse, data: Data) throws -> Any? {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }

        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var decoded: Any?
        if !body.isEmpty {
            do {
                // `.fragmentsAllowed` mirrors Dart `jsonDecode`, which accepts
                // top-level scalar JSON too.
                decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw APIError.invalidResponse(status: http.statusCode)
            }
        }

        if let map = decoded as? [String: Any],
           let payload = map["payload"] as? String {
            guard let value = SecurePayload.decode(payload, key: securePayloadKey) else {
                throw APIError.payloadDecodeFailed(status: http.statusCode)
            }
            decoded = value
        }

        if http.statusCode < 200 || http.statusCode >= 300 {
            let message = (decoded as? [String: Any])?["error"].map { String(describing: $0) }
                ?? "Request failed."
            throw APIError.http(status: http.statusCode, message: message)
        }

        return decoded
    }
}
