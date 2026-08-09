import Foundation

/// Thin wrapper over `UserDefaults`. Views and controllers never touch
/// `UserDefaults` directly; storage keys stay in one place.
struct ArunaStorage {
    enum Key {
        static let watchlist = "aruna.watchlist.v1"
        static let portfolio = "aruna.portfolio.v1"
        static let portfolioSort = "aruna.portfolio.sort.v1"
        static let portfolioCurrency = "portfolio_currency"
        static let themeMode = "aruna_theme_mode"
        static let privacyCensorEnabled = "privacy_censor_enabled"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// Encodes `value` as JSON (Dart-compatible dates) and stores it.
    func setJSON<T: Encodable>(_ value: T, forKey key: String) throws {
        defaults.set(try ArunaStorage.jsonEncoder.encode(value), forKey: key)
    }

    /// UI-test isolation hook: clears persisted settings so tests start from a
    /// known state. Invoked only when the app launches with `-uitest-reset`.
    func clearSettingsForUITests() {
        defaults.removeObject(forKey: Key.themeMode)
        defaults.removeObject(forKey: Key.privacyCensorEnabled)
        defaults.removeObject(forKey: Key.watchlist)
    }

    /// Decodes a JSON value previously stored via `setJSON`.
    func jsonObject<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try ArunaStorage.jsonDecoder.decode(T.self, from: data)
    }

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ArunaDate.isoString(from: date))
        }
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ArunaDate.isoParse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Dart ISO-8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }()
}
