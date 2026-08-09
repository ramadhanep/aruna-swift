import Foundation

/// Exact port of Flutter `SecurePayload.decode` (`lib/core/api/secure_payload.dart`).
///
/// base64-decode payload → UTF-8 encode key → XOR each byte with
/// `key[i % key.count]` → UTF-8 decode → JSON decode. Any invalid input fails
/// cleanly by returning `nil`.
enum SecurePayload {
    static func decode(_ payload: String, key: String) -> Any? {
        guard !payload.isEmpty, !key.isEmpty else { return nil }
        guard let cipherBytes = base64DecodeStrict(payload),
              let keyData = key.data(using: .utf8), !keyData.isEmpty else {
            return nil
        }

        let keyBytes = [UInt8](keyData)
        var plain = [UInt8](repeating: 0, count: cipherBytes.count)
        for i in 0..<cipherBytes.count {
            plain[i] = cipherBytes[i] ^ keyBytes[i % keyBytes.count]
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(plain), options: []) else {
            return nil
        }
        return json
    }

    /// Flutter's `base64Decode` rejects invalid characters. Swift's default
    /// `Data(base64Encoded:)` is lenient, so validate the alphabet first.
    private static func base64DecodeStrict(_ string: String) -> Data? {
        let cleaned = string.replacingOccurrences(of: " ", with: "")
        guard cleaned.rangeOfCharacter(from: base64Alphabet.inverted) == nil else {
            return nil
        }
        return Data(base64Encoded: cleaned)
    }

    private static let base64Alphabet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    )
}
