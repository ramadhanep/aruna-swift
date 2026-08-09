import Foundation

enum APIError: Error, Sendable {
    /// Non-2xx response with (or without) a decoded `error` field.
    case http(status: Int, message: String)
    /// Body was not valid JSON.
    case invalidResponse(status: Int)
    /// `{"payload": ...}` failed to decode with the configured key.
    case payloadDecodeFailed(status: Int?)
    /// Transport-level failure.
    case transport(URLError)

    var statusCode: Int? {
        switch self {
        case .http(let status, _), .invalidResponse(let status):
            return status
        case .payloadDecodeFailed(let status):
            return status
        case .transport:
            return nil
        }
    }

    /// Mirrors Flutter `ApiException.message`.
    var message: String {
        switch self {
        case .http(_, let message):
            return message
        case .invalidResponse:
            return "Server returned a non-JSON response."
        case .payloadDecodeFailed:
            return "Unable to decode the API payload. Check ARUNA_SECURE_PAYLOAD_KEY."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}
