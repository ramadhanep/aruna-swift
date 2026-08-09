import Foundation

/// Port of Flutter `WatchlistItem` (`lib/features/watchlist/data/watchlist_model.dart`).
///
/// JSON contract is byte-compatible with the Dart model: `symbol` (trimmed +
/// uppercased), optional `name`, optional `order`, and `addedAt` as a
/// Dart `toIso8601String()` (six fractional digits, no `Z`).
struct WatchlistItem: Codable, Equatable {
    /// Flutter `defaultWatchlistSymbols` — exact order is preserved.
    static let defaultSymbols = [
        "BBCA.JK",
        "BBRI.JK",
        "BMRI.JK",
        "BTC-USD",
        "QQQ",
        "SPY",
        "NVDA",
        "MSFT",
    ]

    let symbol: String
    let name: String?
    /// 1-based persisted position (Flutter `_dedupe` reindexes as `index + 1`).
    let order: Int?
    let addedAt: Date

    init(symbol: String, name: String? = nil, order: Int? = nil, addedAt: Date = Date()) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.name = name?.isEmpty == true ? nil : name
        self.order = order
        self.addedAt = addedAt
    }

    init(json: [String: Any]) {
        let rawSymbol = (json["symbol"] as? String) ?? ""
        var name: String?
        if let text = json["name"] as? String {
            name = text
        } else if let number = json["name"] as? NSNumber {
            name = number.stringValue
        }
        let addedAtString = (json["addedAt"] as? String) ?? ""
        self.init(
            symbol: rawSymbol,
            name: name,
            order: Self.intValue(json["order"]),
            addedAt: ArunaDate.isoParse(addedAtString) ?? Date()
        )
    }

    // MARK: - Codable (Dart `toJson` / `fromJson`)

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case order
        case addedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawSymbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let addedAtString = try container.decodeIfPresent(String.self, forKey: .addedAt) ?? ""
        self.init(
            symbol: rawSymbol,
            name: name,
            order: try Self.tolerantOrder(container),
            addedAt: ArunaDate.isoParse(addedAtString) ?? Date()
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        if let name, !name.isEmpty {
            try container.encode(name, forKey: .name)
        }
        if let order {
            try container.encode(order, forKey: .order)
        }
        try container.encode(ArunaDate.isoString(from: addedAt), forKey: .addedAt)
    }

    // MARK: - Tolerant parsing (Flutter `_toInt`)

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, number.doubleValue.isFinite {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func tolerantOrder(_ container: KeyedDecodingContainer<CodingKeys>) throws -> Int? {
        if let number = try? container.decode(Double.self, forKey: .order), number.isFinite {
            return Int(number)
        }
        if let text = try? container.decode(String.self, forKey: .order) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
