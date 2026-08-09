import Foundation

// MARK: - Models

/// Port of Flutter `StockQuote` (`lib/core/api/market_models.dart`).
/// Deliberately not Codable: Flutter's fuzzy parsing (numeric strings, commas,
/// percent signs, fallback keys) is preserved 1:1 via `init(json:)`.
struct StockQuote: Sendable, Equatable {
    let symbol: String
    let name: String
    let price: Double?
    let change: Double?
    let changePercent: Double?
    let timeframeChange: Double?
    let logoURL: String?
    let currency: String?
    let chartData: [Double]
    let chartTimestamps: [Date]

    init(json: [String: Any]) {
        let symbol = ArunaJSON.string(json["symbol"]).uppercased()
        let meta = json["meta"] as? [String: Any] ?? [:]
        self.symbol = symbol
        self.name = ArunaJSON.string(json["name"], fallback: symbol)
        self.price = ArunaJSON.number(json["price"])
        self.change = ArunaJSON.number(json["change"])
        self.changePercent = ArunaJSON.number(json["changePercent"])
        self.timeframeChange = ArunaJSON.number(json["timeframeChange"])
        self.logoURL = ArunaJSON.nullableString(json["logo"] ?? json["logoUrl"])
        self.currency = ArunaJSON.nullableString(meta["currency"] ?? json["currency"])
        self.chartData = ArunaJSON.numberList(json["chartData"])
        self.chartTimestamps = ArunaJSON.dateList(json["chartTimestamps"])
    }
}

/// Port of Flutter `SymbolSearchResult`.
struct SymbolSearchResult: Sendable, Equatable {
    let symbol: String
    let name: String
    let exchange: String?
    let type: String?

    init(json: [String: Any]) {
        let symbol = ArunaJSON.string(json["symbol"]).uppercased()
        self.symbol = symbol
        self.name = ArunaJSON.string(
            json["name"] ?? json["shortname"] ?? json["longname"],
            fallback: symbol
        )
        self.exchange = ArunaJSON.nullableString(json["exchange"])
        self.type = ArunaJSON.nullableString(json["type"] ?? json["quoteType"])
    }
}

/// Port of Flutter `PricePoint`.
struct PricePoint: Sendable, Equatable {
    let date: Date
    let price: Double

    init(json: [String: Any]) {
        let rawDate = ArunaJSON.nullableString(json["date"])
        self.date = ArunaDate.isoParse(rawDate ?? "") ?? Date()
        self.price = ArunaJSON.number(json["price"] ?? json["close"] ?? json["adjclose"]) ?? 0
    }
}

/// Port of Flutter `FundamentalsSummary`.
struct FundamentalsSummary: Sendable, Equatable {
    let sector: String?
    let industry: String?
    let exchange: String?
    let marketState: String?
    let marketCap: Double?
    let trailingPe: Double?
    let priceToBook: Double?
    let dividendYield: Double?
    let recommendationKey: String?

    init(json: [String: Any]) {
        let profile = json["profile"] as? [String: Any] ?? [:]
        let valuations = json["valuations"] as? [String: Any] ?? [:]
        let dividendInfo = json["dividendInfo"] as? [String: Any] ?? [:]
        let recommendationDetails =
            (json["recommendations"] as? [String: Any])?["details"] as? [String: Any] ?? [:]

        self.sector = ArunaJSON.nullableString(profile["sector"])
        self.industry = ArunaJSON.nullableString(profile["industry"])
        self.exchange = ArunaJSON.nullableString(profile["exchange"])
        self.marketState = ArunaJSON.nullableString(profile["marketState"])
        self.marketCap = ArunaJSON.number(valuations["marketCap"])
        self.trailingPe = ArunaJSON.number(valuations["trailingPe"])
        self.priceToBook = ArunaJSON.number(valuations["priceToBook"])
        self.dividendYield = ArunaJSON.number(dividendInfo["dividendYield"])
        self.recommendationKey = ArunaJSON.nullableString(recommendationDetails["recommendationKey"])
    }
}

// MARK: - JSON extraction helpers (port of private helpers in market_models.dart)

enum ArunaJSON {
    static func string(_ value: Any?, fallback: String = "") -> String {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return fallback
        }
        return text
    }

    static func nullableString(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let text = value as? String {
            let cleaned = text
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let double = Double(cleaned), double.isFinite else { return nil }
            return double
        }
        return nil
    }

    static func numberList(_ value: Any?) -> [Double] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { number($0) }
    }

    static func dateList(_ value: Any?) -> [Date] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { entry -> Date? in
            guard let text = entry as? String else { return nil }
            return ArunaDate.isoParse(text)
        }
    }
}
