import Foundation

/// Port of Flutter `MarketRepository` (`lib/core/api/market_repository.dart`).
struct MarketRepository: Sendable {
    let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchQuotes(_ symbols: [String], timeframe: String = "1D") async throws -> [String: StockQuote] {
        let unique = symbols
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, symbol in
                if !result.contains(symbol) { result.append(symbol) }
            }
        guard !unique.isEmpty else { return [:] }

        guard let data = try await apiClient.post("/quotes", body: ["symbols": unique, "timeframe": timeframe]) else {
            return [:]
        }

        if let map = data as? [String: Any], let quotes = map["quotes"] as? [String: Any] {
            var result: [String: StockQuote] = [:]
            for (_, value) in quotes {
                guard let json = value as? [String: Any] else { continue }
                let quote = StockQuote(json: json)
                result[quote.symbol] = quote
            }
            return result
        }

        if let list = data as? [[String: Any]] {
            var result: [String: StockQuote] = [:]
            for json in list {
                let quote = StockQuote(json: json)
                result[quote.symbol] = quote
            }
            return result
        }

        return [:]
    }

    func searchSymbols(_ query: String) async throws -> [SymbolSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let data = try await apiClient.get("/symbol-search", query: ["q": trimmed])
        let raw: [Any]
        if let map = data as? [String: Any], let symbols = map["symbols"] as? [Any] {
            raw = symbols
        } else if let list = data as? [Any] {
            raw = list
        } else {
            raw = []
        }

        return raw.compactMap { $0 as? [String: Any] }.map { SymbolSearchResult(json: $0) }
    }

    func fetchPriceSeries(_ symbol: String, timeframe: String = "D") async throws -> [PricePoint] {
        let data = try await apiClient.get(
            "/price-series",
            query: ["symbol": symbol.trimmingCharacters(in: .whitespaces).uppercased(), "timeframe": timeframe]
        )
        let raw: [Any]
        if let map = data as? [String: Any], let points = map["data"] as? [Any] {
            raw = points
        } else if let map = data as? [String: Any], let points = map["quotes"] as? [Any] {
            raw = points
        } else if let list = data as? [Any] {
            raw = list
        } else {
            raw = []
        }

        return raw
            .compactMap { $0 as? [String: Any] }
            .map { PricePoint(json: $0) }
            .filter { $0.price > 0 }
    }

    func fetchFundamentals(_ symbol: String) async throws -> FundamentalsSummary? {
        let data = try await apiClient.get(
            "/fundamentals",
            query: ["symbol": symbol.trimmingCharacters(in: .whitespaces).uppercased()]
        )
        guard let json = data as? [String: Any] else { return nil }
        return FundamentalsSummary(json: json)
    }

    func fetchLatestFinancePrice(_ symbol: String) async throws -> Double? {
        let now = Date()
        let endDate = Int(now.timeIntervalSince1970)
        let startDate = Int(now.addingTimeInterval(-5 * 86_400).timeIntervalSince1970)

        let data = try await apiClient.get(
            "/finance",
            query: [
                "symbol": symbol.trimmingCharacters(in: .whitespaces).uppercased(),
                "startDate": endDate <= startDate ? nil : String(startDate),
                "endDate": String(endDate),
            ]
        )
        let raw: [Any]
        if let map = data as? [String: Any], let rows = map["data"] as? [Any] {
            raw = rows
        } else if let list = data as? [Any] {
            raw = list
        } else {
            raw = []
        }

        for row in raw.reversed() {
            guard let json = row as? [String: Any] else { continue }
            if let price = ArunaJSON.number(json["adjclose"] ?? json["close"] ?? json["price"]),
               price > 0 {
                return price
            }
        }
        return nil
    }
}
