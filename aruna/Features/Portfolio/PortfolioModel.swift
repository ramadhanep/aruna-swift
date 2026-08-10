import Foundation

/// Port of Flutter `PortfolioDisplayCurrency`.
enum PortfolioDisplayCurrency: String, CaseIterable {
    case idr
    case usd
    case sgd

    /// Upper-case stored code (`IDR`/`USD`/`SGD`).
    var code: String {
        switch self {
        case .idr: return "IDR"
        case .usd: return "USD"
        case .sgd: return "SGD"
        }
    }
}

/// Port of Flutter `PortfolioSortOption`. Raw values are the Dart enum `name`
/// and persist under `aruna.portfolio.sort.v1`.
enum PortfolioSortOption: String, CaseIterable {
    case symbol
    case currentValue
    case profitLossAmount
    case profitLossPercent
    case newestFirst
    case oldestFirst

    var label: String {
        switch self {
        case .symbol: return "Symbol"
        case .currentValue: return "Current value"
        case .profitLossAmount: return "P/L amount"
        case .profitLossPercent: return "P/L %"
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }

    var shortLabel: String {
        switch self {
        case .symbol: return "Symbol"
        case .currentValue: return "Value"
        case .profitLossAmount: return "P/L"
        case .profitLossPercent: return "P/L %"
        case .newestFirst: return "Newest"
        case .oldestFirst: return "Oldest"
        }
    }
}

func portfolioDisplayCurrencyCode(_ currency: PortfolioDisplayCurrency) -> String {
    currency.code
}

/// Port of Flutter `PortfolioHolding` (`lib/features/portfolio/data/portfolio_model.dart`).
///
/// JSON contract is byte-compatible with the Dart model: both legacy and new
/// aliases are written on encode (`quantity`+`amount`, `averagePrice`+`avgPrice`)
/// and accepted on decode (`createdAt`+`created_at`), so previously stored
/// Supabase rows decode unchanged.
struct PortfolioHolding: Codable, Equatable {
    static let defaultCashEmoji = "💵"

    let id: String
    let symbol: String
    let quantity: Double
    let averagePrice: Double
    let name: String?
    let type: String?
    let unit: String?
    let currency: String?
    let market: String?
    let assetType: String?
    let category: String?
    let cashCurrency: String?
    let nativeAmount: Double?
    let emoji: String?
    let createdAt: Date

    // MARK: - Derived (Flutter getters)

    var isCash: Bool { type == "cash" || symbol.hasPrefix("CASH_") }
    var isLot: Bool { unit == "lot" }
    var effectiveQuantity: Double {
        if isCash { return quantity }
        if isLot { return quantity * 100 }
        return quantity
    }
    var cost: Double { effectiveQuantity * averagePrice }
    var displayName: String { category ?? name ?? symbol }
    var cashEmoji: String {
        guard let emoji, !emoji.isEmpty else { return Self.defaultCashEmoji }
        return emoji
    }

    /// Direct construction. Callers pass already-normalized values (this is the
    /// path the controller uses to build save payloads).
    init(
        id: String,
        symbol: String,
        quantity: Double,
        averagePrice: Double,
        name: String? = nil,
        type: String? = nil,
        unit: String? = nil,
        currency: String? = nil,
        market: String? = nil,
        assetType: String? = nil,
        category: String? = nil,
        cashCurrency: String? = nil,
        nativeAmount: Double? = nil,
        emoji: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.averagePrice = averagePrice
        self.name = name
        self.type = type
        self.unit = unit
        self.currency = currency
        self.market = market
        self.assetType = assetType
        self.category = category
        self.cashCurrency = cashCurrency
        self.nativeAmount = nativeAmount
        self.emoji = emoji
        self.createdAt = createdAt ?? Date()
    }

    /// Port of Flutter `PortfolioHolding.fromJson` — applies all normalization
    /// rules (uppercase symbol, cash detection, unit inference, legacy aliases).
    init(json: [String: Any]) {
        let symbol = ((json["symbol"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let rawType = Self.nullableString(json["type"])
        let type = Self.normalizeType(rawType, symbol: symbol)
        let cashCurrency = Self.nullableString(json["cashCurrency"])?.uppercased()
        let quantity = Self.toDouble(json["quantity"] ?? json["amount"])
        let averagePrice = Self.toDouble(json["averagePrice"] ?? json["avgPrice"])
        let id = (json["id"] as? String) ?? "\(symbol)_\(Self.microsNow())"
        let unit = Self.normalizeUnit(Self.nullableString(json["unit"]), symbol: symbol, type: type)
        let legacyAssetType = Self.assetTypeFromLegacy(Self.nullableString(json["type"]), symbol: symbol)
        let createdAtString = ((json["createdAt"] as? String) ?? (json["created_at"] as? String)) ?? ""

        self.init(
            id: id,
            symbol: symbol,
            quantity: quantity,
            averagePrice: averagePrice,
            name: Self.nullableString(json["name"]),
            type: type,
            unit: unit,
            currency: Self.nullableString(json["currency"])?.uppercased(),
            market: Self.nullableString(json["market"]),
            assetType: Self.nullableString(json["assetType"]) ?? legacyAssetType,
            category: Self.nullableString(json["category"]),
            cashCurrency: cashCurrency ?? (type == "cash" ? Self.cashCurrencyFromSymbol(symbol) : nil),
            nativeAmount: Self.toNullableDouble(json["nativeAmount"]),
            emoji: Self.nullableString(json["emoji"]),
            createdAt: ArunaDate.isoParse(createdAtString)
        )
    }

    /// Port of Flutter `toJson` — redundant alias fields are preserved exactly.
    func toJSON() -> [String: Any] {
        let normalizedType = type == "cash" ? "cash" : "digital"
        let webType: String
        if let assetType, !assetType.isEmpty {
            webType = assetType
        } else {
            webType = normalizedType
        }

        var json: [String: Any] = [
            "id": id,
            "symbol": symbol,
            "quantity": quantity,
            "amount": quantity,
            "averagePrice": averagePrice,
            "avgPrice": averagePrice,
            "unit": unit ?? "share",
            "type": normalizedType == "cash" ? "cash" : webType,
            "createdAt": ArunaDate.isoString(from: createdAt),
        ]
        if let name, !name.isEmpty { json["name"] = name }
        if let currency, !currency.isEmpty { json["currency"] = currency }
        if let market, !market.isEmpty { json["market"] = market }
        if let assetType, !assetType.isEmpty { json["assetType"] = assetType }
        if let category, !category.isEmpty { json["category"] = category }
        if let cashCurrency, !cashCurrency.isEmpty { json["cashCurrency"] = cashCurrency }
        if let nativeAmount { json["nativeAmount"] = nativeAmount }
        if let emoji, !emoji.isEmpty { json["emoji"] = emoji }
        return json
    }

    // MARK: - Codable (Dart `toJson` / `fromJson` for local persistence)

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case quantity
        case amount
        case averagePrice
        case avgPrice
        case unit
        case currency
        case market
        case assetType
        case type
        case category
        case cashCurrency
        case nativeAmount
        case emoji
        case createdAt
        case createdAtLegacy = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let symbol = ((try? container.decode(String.self, forKey: .symbol)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let rawType = try? container.decode(String.self, forKey: .type)
        let type = Self.normalizeType(rawType, symbol: symbol)
        let quantity = Self.decodeDouble(container, keys: [.quantity, .amount]) ?? 0
        let averagePrice = Self.decodeDouble(container, keys: [.averagePrice, .avgPrice]) ?? 0
        let id = (try? container.decode(String.self, forKey: .id)) ?? "\(symbol)_\(Self.microsNow())"
        let unit = Self.normalizeUnit(Self.decodeString(container, .unit), symbol: symbol, type: type)
        let legacyAssetType = Self.assetTypeFromLegacy(Self.decodeString(container, .type), symbol: symbol)
        let createdAtString =
            (try? container.decode(String.self, forKey: .createdAt))
            ?? (try? container.decode(String.self, forKey: .createdAtLegacy))
            ?? ""

        self.init(
            id: id,
            symbol: symbol,
            quantity: quantity,
            averagePrice: averagePrice,
            name: Self.decodeString(container, .name),
            type: type,
            unit: unit,
            currency: Self.decodeString(container, .currency)?.uppercased(),
            market: Self.decodeString(container, .market),
            assetType: Self.decodeString(container, .assetType) ?? legacyAssetType,
            category: Self.decodeString(container, .category),
            cashCurrency: Self.decodeString(container, .cashCurrency)?.uppercased()
                ?? (type == "cash" ? Self.cashCurrencyFromSymbol(symbol) : nil),
            nativeAmount: Self.decodeNullableDouble(container, [.nativeAmount]),
            emoji: Self.decodeString(container, .emoji),
            createdAt: ArunaDate.isoParse(createdAtString)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(symbol, forKey: .symbol)
        if let name, !name.isEmpty { try container.encode(name, forKey: .name) }
        try container.encode(quantity, forKey: .quantity)
        try container.encode(quantity, forKey: .amount)
        try container.encode(averagePrice, forKey: .averagePrice)
        try container.encode(averagePrice, forKey: .avgPrice)
        try container.encode(unit ?? "share", forKey: .unit)
        if let currency, !currency.isEmpty { try container.encode(currency, forKey: .currency) }
        if let market, !market.isEmpty { try container.encode(market, forKey: .market) }
        if let assetType, !assetType.isEmpty { try container.encode(assetType, forKey: .assetType) }

        let normalizedType = type == "cash" ? "cash" : "digital"
        let webType = (assetType?.isEmpty == false) ? assetType! : normalizedType
        try container.encode(normalizedType == "cash" ? "cash" : webType, forKey: .type)

        if let category, !category.isEmpty { try container.encode(category, forKey: .category) }
        if let cashCurrency, !cashCurrency.isEmpty { try container.encode(cashCurrency, forKey: .cashCurrency) }
        if let nativeAmount { try container.encode(nativeAmount, forKey: .nativeAmount) }
        if let emoji, !emoji.isEmpty { try container.encode(emoji, forKey: .emoji) }
        try container.encode(ArunaDate.isoString(from: createdAt), forKey: .createdAt)
    }

    // MARK: - Normalization helpers (port of private functions in portfolio_model.dart)

    static func normalizeType(_ type: String?, symbol: String) -> String {
        let normalized = type?.trimmingCharacters(in: .whitespaces).lowercased()
        if normalized == "cash" || symbol.hasPrefix("CASH_") {
            return "cash"
        }
        return "digital"
    }

    static func normalizeUnit(_ value: String?, symbol: String, type: String) -> String? {
        if type == "cash" {
            return "unit"
        }
        let normalized = nullableString(value)?.lowercased()
        if normalized == "lot" || normalized == "share" {
            return normalized
        }
        return symbol.hasSuffix(".JK") ? "lot" : "share"
    }

    static func cashCurrencyFromSymbol(_ symbol: String) -> String? {
        guard symbol.hasPrefix("CASH_") else { return nil }
        let currency = symbol
            .replacingOccurrences(of: "CASH_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return currency.isEmpty ? nil : currency
    }

    static func assetTypeFromLegacy(_ value: String?, symbol: String) -> String? {
        let raw = nullableString(value)?.lowercased()
        if raw == nil || raw == "digital" || raw == "cash" {
            return symbol.hasSuffix("-USD") ? "crypto" : "stock"
        }
        return raw
    }

    static func nullableString(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    static func toDouble(_ value: Any?) -> Double {
        if let number = value as? NSNumber, number.doubleValue.isFinite {
            return number.doubleValue
        }
        if let text = value as? String {
            let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            return Double(cleaned) ?? 0
        }
        return 0
    }

    static func toNullableDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, number.doubleValue.isFinite {
            return number.doubleValue
        }
        if let text = value as? String {
            let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    private static func microsNow() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000_000)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        (try? container.decode(String.self, forKey: key))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Double? {
        for key in keys {
            if let number = try? container.decodeIfPresent(Double.self, forKey: key),
               number.isFinite {
                return number
            }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) {
                let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                if let value = Double(cleaned), value.isFinite {
                    return value
                }
            }
        }
        return nil
    }

    private static func decodeNullableDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ keys: [CodingKeys]
    ) -> Double? {
        decodeDouble(container, keys: keys)
    }
}
