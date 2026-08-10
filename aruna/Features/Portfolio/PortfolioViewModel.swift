import Foundation
import Observation

// MARK: - Runtime state types (port of portfolio_controller.dart)

struct PortfolioFxRates: Equatable {
    var idrPerUsd: Double?
    var sgdPerUsd: Double?

    var hasIdr: Bool { idrPerUsd != nil && idrPerUsd! > 0 }
    var hasSgd: Bool { sgdPerUsd != nil && sgdPerUsd! > 0 }
}

struct PortfolioSummary: Equatable {
    let totalValue: Double
    let totalCost: Double
    let digitalValue: Double
    let digitalCost: Double
    let cashValue: Double
    let currency: PortfolioDisplayCurrency

    var profitLoss: Double { totalValue - totalCost }
    var profitLossPercent: Double {
        totalCost == 0 ? 0 : (profitLoss / totalCost) * 100
    }
    var digitalProfitLoss: Double { digitalValue - digitalCost }
    var digitalProfitLossPercent: Double {
        digitalCost == 0 ? 0 : (digitalProfitLoss / digitalCost) * 100
    }
}

struct PortfolioDistributionItem: Equatable {
    let label: String
    let value: Double
    let valueUSD: Double
}

struct PortfolioHoldingMetrics: Equatable {
    let holding: PortfolioHolding
    let quote: StockQuote?
    let currentValue: Double
    let costBasis: Double
    let currentValueUSD: Double
    let costBasisUSD: Double
    let profitLoss: Double
    let profitLossPercent: Double
    let displayQuantity: Double
    let nativeCashValue: Double?
    let currency: String?
}

struct PortfolioPositionContext: Equatable {
    let symbol: String
    let quantity: Double
    let averageCost: Double
    let costBasis: Double
    let currentValue: Double
    let unrealizedGain: Double
    let unrealizedGainPercent: Double
    let currency: String?
}

struct PortfolioState: Equatable {
    let holdings: [PortfolioHolding]
    let positions: [PortfolioHoldingMetrics]
    let digitalPositions: [PortfolioHoldingMetrics]
    let cashPositions: [PortfolioHoldingMetrics]
    let quotes: [String: StockQuote]
    let summary: PortfolioSummary
    let sortOption: PortfolioSortOption
    let displayCurrency: PortfolioDisplayCurrency
    let effectiveCurrency: PortfolioDisplayCurrency
    let fxRates: PortfolioFxRates
    let assetTypeDistribution: [PortfolioDistributionItem]
    let digitalDistribution: [PortfolioDistributionItem]
    let cashDistribution: [PortfolioDistributionItem]
    let holdingsDistribution: [PortfolioDistributionItem]
    let quoteError: String?
    let fxError: String?

    /// Port of `positionFor(symbol)`: aggregates digital positions by symbol.
    func positionFor(_ symbol: String) -> PortfolioPositionContext? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let matches = digitalPositions.filter { $0.holding.symbol == normalized }
        guard !matches.isEmpty else { return nil }

        let quantity = matches.reduce(0) { $0 + $1.displayQuantity }
        let costBasis = matches.reduce(0) { $0 + $1.costBasis }
        let currentValue = matches.reduce(0) { $0 + $1.currentValue }
        let unrealizedGain = currentValue - costBasis
        let averageCost = quantity == 0 ? 0 : costBasis / quantity

        return PortfolioPositionContext(
            symbol: normalized,
            quantity: quantity,
            averageCost: averageCost,
            costBasis: costBasis,
            currentValue: currentValue,
            unrealizedGain: unrealizedGain,
            unrealizedGainPercent: costBasis == 0 ? 0 : (unrealizedGain / costBasis) * 100,
            currency: currencyCode(effectiveCurrency)
        )
    }
}

func currencyCode(_ currency: PortfolioDisplayCurrency) -> String {
    switch currency {
    case .idr: return "IDR"
    case .usd: return "USD"
    case .sgd: return "SGD"
    }
}

/// Port of Flutter `PortfolioController` (AsyncNotifier → state).
@MainActor
@Observable
final class PortfolioViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var state: PortfolioState?

    let repository: PortfolioRepository
    let market: MarketRepository

    init(repository: PortfolioRepository, market: MarketRepository) {
        self.repository = repository
        self.market = market
    }

    // MARK: - Load / refresh

    /// Initial load: holdings + sort + display currency → FX + quotes → state.
    func load() async {
        phase = .loading
        do {
            let holdings = try await repository.load()
            let sortOption = repository.loadSortOption()
            let displayCurrency = repository.loadDisplayCurrency()
            state = await buildState(
                holdings: holdings,
                sortOption: sortOption,
                displayCurrency: displayCurrency,
                previousFxRates: nil
            )
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Pull-to-refresh: rebuild state using current holdings + FX, keeping
    /// previously fetched FX on failure. Never destroys persisted holdings.
    func refreshQuotes() async {
        guard let current = state else { return }
        state = await buildState(
            holdings: current.holdings,
            sortOption: current.sortOption,
            displayCurrency: current.displayCurrency,
            previousFxRates: current.fxRates
        )
    }

    // MARK: - Mutations

    func addHolding(
        symbol: String,
        quantity: Double,
        averagePrice: Double,
        currency: String? = nil,
        market: String? = nil,
        assetType: String? = nil,
        type: String? = nil,
        unit: String? = nil,
        name: String? = nil,
        category: String? = nil,
        cashCurrency: String? = nil,
        nativeAmount: Double? = nil,
        emoji: String? = nil
    ) async throws {
        let current = state
        guard let built = buildHoldingForSave(
            id: nil, createdAt: nil, symbol: symbol, quantity: quantity, averagePrice: averagePrice,
            currency: currency, market: market, assetType: assetType, type: type, unit: unit,
            name: name, category: category, cashCurrency: cashCurrency, nativeAmount: nativeAmount,
            emoji: emoji, fxRates: current?.fxRates ?? PortfolioFxRates()
        ) else { return }

        let nextHoldings = [built] + (current?.holdings ?? [])
        let saved = try await repository.save(nextHoldings)
        state = await buildState(
            holdings: saved,
            sortOption: current?.sortOption ?? .symbol,
            displayCurrency: current?.displayCurrency ?? .idr,
            previousFxRates: current?.fxRates
        )
    }

    func updateHolding(
        id: String,
        symbol: String,
        quantity: Double,
        averagePrice: Double,
        currency: String? = nil,
        market: String? = nil,
        assetType: String? = nil,
        type: String? = nil,
        unit: String? = nil,
        name: String? = nil,
        category: String? = nil,
        cashCurrency: String? = nil,
        nativeAmount: Double? = nil,
        emoji: String? = nil
    ) async throws {
        guard let current = state, !id.isEmpty,
              let existing = current.holdings.first(where: { $0.id == id }) else { return }

        guard let updated = buildHoldingForSave(
            id: id, createdAt: existing.createdAt, symbol: symbol, quantity: quantity, averagePrice: averagePrice,
            currency: currency, market: market, assetType: assetType, type: type, unit: unit,
            name: name, category: category, cashCurrency: cashCurrency, nativeAmount: nativeAmount,
            emoji: emoji, fxRates: current.fxRates
        ) else { return }

        let nextHoldings = current.holdings.map { $0.id == id ? updated : $0 }
        let saved = try await repository.save(nextHoldings)
        state = await buildState(
            holdings: saved,
            sortOption: current.sortOption,
            displayCurrency: current.displayCurrency,
            previousFxRates: current.fxRates
        )
    }

    func removeHolding(id: String) async throws {
        guard let current = state else { return }
        let nextHoldings = current.holdings.filter { $0.id != id }
        let saved = try await repository.save(nextHoldings)
        state = await buildState(
            holdings: saved,
            sortOption: current.sortOption,
            displayCurrency: current.displayCurrency,
            previousFxRates: current.fxRates
        )
    }

    func setSortOption(_ option: PortfolioSortOption) async {
        guard let current = state, current.sortOption != option else { return }
        repository.saveSortOption(option)
        state = buildStateFromQuotes(
            holdings: current.holdings,
            quotes: current.quotes,
            fxRates: current.fxRates,
            displayCurrency: current.displayCurrency,
            quoteError: current.quoteError,
            fxError: current.fxError,
            sortOption: option
        )
    }

    func setDisplayCurrency(_ currency: PortfolioDisplayCurrency) async {
        guard let current = state, current.displayCurrency != currency else { return }
        repository.saveDisplayCurrency(currency)
        state = buildStateFromQuotes(
            holdings: current.holdings,
            quotes: current.quotes,
            fxRates: current.fxRates,
            displayCurrency: currency,
            quoteError: current.quoteError,
            fxError: current.fxError,
            sortOption: current.sortOption
        )
    }

    func positionFor(_ symbol: String) -> PortfolioPositionContext? {
        state?.positionFor(symbol)
    }

    // MARK: - State building

    private func buildState(
        holdings: [PortfolioHolding],
        sortOption: PortfolioSortOption,
        displayCurrency: PortfolioDisplayCurrency,
        previousFxRates: PortfolioFxRates?
    ) async -> PortfolioState {
        let fxResult = await fetchFxRates(previous: previousFxRates)
        var quotes: [String: StockQuote] = [:]
        var quoteError: String?
        do {
            quotes = try await market.fetchQuotes(quoteSymbols(holdings))
        } catch {
            quoteError = String(describing: error)
        }
        return buildStateFromQuotes(
            holdings: holdings,
            quotes: quotes,
            fxRates: fxResult.rates,
            displayCurrency: displayCurrency,
            quoteError: quoteError,
            fxError: fxResult.error,
            sortOption: sortOption
        )
    }

    private func buildStateFromQuotes(
        holdings: [PortfolioHolding],
        quotes: [String: StockQuote],
        fxRates: PortfolioFxRates,
        displayCurrency: PortfolioDisplayCurrency,
        quoteError: String?,
        fxError: String?,
        sortOption: PortfolioSortOption
    ) -> PortfolioState {
        let effectiveCurrency = effectiveDisplayCurrency(displayCurrency, fxRates)
        let metrics = buildMetrics(holdings, quotes: quotes, fxRates: fxRates, displayCurrency: effectiveCurrency)
        let grouped = sortGrouped(metrics, option: sortOption)
        let digitalPositions = grouped.digital
        let cashPositions = grouped.cash
        let positions = digitalPositions + cashPositions

        let digitalValueUSD = digitalPositions.reduce(0) { $0 + $1.currentValueUSD }
        let digitalCostUSD = digitalPositions.reduce(0) { $0 + $1.costBasisUSD }
        let cashValueUSD = cashPositions.reduce(0) { $0 + $1.currentValueUSD }
        let totalValueUSD = digitalValueUSD + cashValueUSD
        let totalCostUSD = digitalCostUSD + cashValueUSD

        let summary = PortfolioSummary(
            totalValue: usdToDisplay(totalValueUSD, effectiveCurrency, fxRates),
            totalCost: usdToDisplay(totalCostUSD, effectiveCurrency, fxRates),
            digitalValue: usdToDisplay(digitalValueUSD, effectiveCurrency, fxRates),
            digitalCost: usdToDisplay(digitalCostUSD, effectiveCurrency, fxRates),
            cashValue: usdToDisplay(cashValueUSD, effectiveCurrency, fxRates),
            currency: effectiveCurrency
        )

        let assetTypeDistribution = [
            PortfolioDistributionItem(label: "Digital Assets", value: summary.digitalValue, valueUSD: digitalValueUSD),
            PortfolioDistributionItem(label: "Cash", value: summary.cashValue, valueUSD: cashValueUSD),
        ].filter { $0.valueUSD > 0 }

        let digitalDistribution = digitalPositions.map {
            PortfolioDistributionItem(label: $0.holding.symbol, value: $0.currentValue, valueUSD: $0.currentValueUSD)
        }

        let cashDistribution = cashByCurrency(
            cashPositions,
            displayCurrency: effectiveCurrency,
            fxRates: fxRates
        )

        let holdingsDistribution = positions.map {
            PortfolioDistributionItem(label: $0.holding.displayName, value: $0.currentValue, valueUSD: $0.currentValueUSD)
        }

        return PortfolioState(
            holdings: holdings,
            positions: positions,
            digitalPositions: digitalPositions,
            cashPositions: cashPositions,
            quotes: quotes,
            summary: summary,
            sortOption: sortOption,
            displayCurrency: displayCurrency,
            effectiveCurrency: effectiveCurrency,
            fxRates: fxRates,
            assetTypeDistribution: assetTypeDistribution,
            digitalDistribution: digitalDistribution,
            cashDistribution: cashDistribution,
            holdingsDistribution: holdingsDistribution,
            quoteError: quoteError,
            fxError: fxError
        )
    }

    // MARK: - Metrics

    private func buildMetrics(
        _ holdings: [PortfolioHolding],
        quotes: [String: StockQuote],
        fxRates: PortfolioFxRates,
        displayCurrency: PortfolioDisplayCurrency
    ) -> [PortfolioHoldingMetrics] {
        holdings.map { holding in
            if holding.isCash {
                let costBasisUSD = holding.averagePrice * holding.quantity
                let currentValue = usdToDisplay(costBasisUSD, displayCurrency, fxRates)
                return PortfolioHoldingMetrics(
                    holding: holding,
                    quote: nil,
                    currentValue: currentValue,
                    costBasis: currentValue,
                    currentValueUSD: costBasisUSD,
                    costBasisUSD: costBasisUSD,
                    profitLoss: 0,
                    profitLossPercent: 0,
                    displayQuantity: holding.nativeAmount ?? holding.quantity,
                    nativeCashValue: cashNativeValue(holding, fxRates),
                    currency: currencyCode(displayCurrency)
                )
            }

            let quote = quotes[holding.symbol]
            let currentNativePrice = quote?.price ?? holding.averagePrice
            let currentValueUSD = nativePriceToUSD(holding.symbol, currentNativePrice, fxRates)
                * holding.effectiveQuantity
            let costBasisUSD = nativePriceToUSD(holding.symbol, holding.averagePrice, fxRates)
                * holding.effectiveQuantity
            let currentValue = usdToDisplay(currentValueUSD, displayCurrency, fxRates)
            let costBasis = usdToDisplay(costBasisUSD, displayCurrency, fxRates)
            let profitLoss = currentValue - costBasis
            let profitLossPercent = costBasis == 0 ? 0 : (profitLoss / costBasis) * 100

            return PortfolioHoldingMetrics(
                holding: holding,
                quote: quote,
                currentValue: currentValue,
                costBasis: costBasis,
                currentValueUSD: currentValueUSD,
                costBasisUSD: costBasisUSD,
                profitLoss: profitLoss,
                profitLossPercent: profitLossPercent,
                displayQuantity: holding.effectiveQuantity,
                nativeCashValue: nil,
                currency: currencyCode(displayCurrency)
            )
        }
    }

    // MARK: - Sorting (port of `_sortGroupedMetrics`)

    private func sortGrouped(
        _ positions: [PortfolioHoldingMetrics],
        option: PortfolioSortOption
    ) -> (digital: [PortfolioHoldingMetrics], cash: [PortfolioHoldingMetrics]) {
        let digital = positions.filter { !$0.holding.isCash }
        let cash = positions.filter { $0.holding.isCash }

        func order(
            _ a: PortfolioHoldingMetrics,
            _ b: PortfolioHoldingMetrics,
            fallback: (PortfolioHoldingMetrics, PortfolioHoldingMetrics) -> Bool
        ) -> Bool {
            let primary: Int
            switch option {
            case .symbol:
                primary = 0
            case .currentValue:
                primary = descending(a.currentValueUSD, b.currentValueUSD)
            case .profitLossAmount:
                primary = descending(a.profitLoss, b.profitLoss)
            case .profitLossPercent:
                primary = descending(a.profitLossPercent, b.profitLossPercent)
            case .newestFirst:
                primary = descending(a.holding.createdAt.timeIntervalSince1970, b.holding.createdAt.timeIntervalSince1970)
            case .oldestFirst:
                primary = ascending(a.holding.createdAt.timeIntervalSince1970, b.holding.createdAt.timeIntervalSince1970)
            }
            if primary != 0 { return primary < 0 }
            return fallback(a, b)
        }

        let digitalSorted = digital.sorted {
            order($0, $1, fallback: { a, b in a.holding.symbol < b.holding.symbol })
        }
        let cashSorted = cash.sorted {
            order($0, $1, fallback: { a, b in a.holding.displayName < b.holding.displayName })
        }
        return (digitalSorted, cashSorted)
    }

    private func ascending(_ lhs: Double, _ rhs: Double) -> Int {
        if lhs < rhs { return -1 }
        if lhs > rhs { return 1 }
        return 0
    }

    private func descending(_ lhs: Double, _ rhs: Double) -> Int {
        -ascending(lhs, rhs)
    }

    // MARK: - Distributions

    private func cashByCurrency(
        _ cashPositions: [PortfolioHoldingMetrics],
        displayCurrency: PortfolioDisplayCurrency,
        fxRates: PortfolioFxRates
    ) -> [PortfolioDistributionItem] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for position in cashPositions {
            let code = position.holding.cashCurrency ?? "USD"
            if totals[code] == nil { order.append(code) }
            totals[code, default: 0] += position.currentValueUSD
        }
        return order.map { code in
            PortfolioDistributionItem(
                label: code,
                value: usdToDisplay(totals[code] ?? 0, displayCurrency, fxRates),
                valueUSD: totals[code] ?? 0
            )
        }
    }

    // MARK: - Save payload builder (port of `_buildHoldingForSave`)

    private func buildHoldingForSave(
        id: String?,
        createdAt: Date?,
        symbol: String,
        quantity: Double,
        averagePrice: Double,
        currency: String?,
        market: String?,
        assetType: String?,
        type: String?,
        unit: String?,
        name: String?,
        category: String?,
        cashCurrency: String?,
        nativeAmount: Double?,
        emoji: String?,
        fxRates: PortfolioFxRates
    ) -> PortfolioHolding? {
        let normalizedType = type == "cash" ? "cash" : "digital"

        if normalizedType == "cash" {
            let code = cleanUpper(cashCurrency) ?? "IDR"
            let amount = nativeAmount ?? quantity
            if amount <= 0 { return nil }
            guard let usdValue = cashValueToUSD(amount, code: code, fxRates: fxRates) else { return nil }
            let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (trimmedCategory?.isEmpty == false) ? trimmedCategory! : "Cash \(code)"
            return PortfolioHolding(
                id: id ?? "CASH_\(code)_\(microsNow())",
                symbol: "CASH_\(code)",
                quantity: 1,
                averagePrice: usdValue,
                name: label,
                type: "cash",
                unit: "unit",
                category: label,
                cashCurrency: code,
                nativeAmount: amount,
                emoji: cleanEmoji(emoji),
                createdAt: createdAt
            )
        }

        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.isEmpty || quantity <= 0 || averagePrice < 0 { return nil }

        return PortfolioHolding(
            id: id ?? "\(normalized)_\(microsNow())",
            symbol: normalized,
            quantity: quantity,
            averagePrice: averagePrice,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines),
            type: "digital",
            unit: cleanUnit(unit, symbol: normalized),
            currency: cleanUpper(currency),
            market: cleanUpper(market),
            assetType: cleanAssetType(assetType, symbol: normalized),
            createdAt: createdAt
        )
    }

    // MARK: - FX

    private func fetchFxRates(previous: PortfolioFxRates?) async -> (rates: PortfolioFxRates, error: String?) {
        var idrPerUsd = previous?.idrPerUsd
        var sgdPerUsd = previous?.sgdPerUsd
        var errors: [String] = []

        do {
            if let latest = try await market.fetchLatestFinancePrice("IDR=X"), latest > 0 {
                idrPerUsd = latest
            } else {
                errors.append("IDR FX unavailable")
            }
        } catch {
            errors.append("IDR FX unavailable")
        }

        do {
            if let latest = try await market.fetchLatestFinancePrice("SGD=X"), latest > 0 {
                sgdPerUsd = latest
            } else {
                errors.append("SGD FX unavailable")
            }
        } catch {
            errors.append("SGD FX unavailable")
        }

        return (
            PortfolioFxRates(idrPerUsd: idrPerUsd, sgdPerUsd: sgdPerUsd),
            errors.isEmpty ? nil : errors.joined(separator: ". ")
        )
    }

    private func nativePriceToUSD(_ symbol: String, _ price: Double?, _ fxRates: PortfolioFxRates) -> Double {
        let value = price ?? 0
        if symbol.hasSuffix(".JK") {
            return fxRates.hasIdr ? value / fxRates.idrPerUsd! : value
        }
        return value
    }

    private func usdToDisplay(
        _ usdAmount: Double,
        _ currency: PortfolioDisplayCurrency,
        _ fxRates: PortfolioFxRates
    ) -> Double {
        switch currency {
        case .idr where fxRates.hasIdr:
            return usdAmount * fxRates.idrPerUsd!
        case .sgd where fxRates.hasSgd:
            return usdAmount * fxRates.sgdPerUsd!
        default:
            return usdAmount
        }
    }

    private func effectiveDisplayCurrency(
        _ currency: PortfolioDisplayCurrency,
        _ fxRates: PortfolioFxRates
    ) -> PortfolioDisplayCurrency {
        switch currency {
        case .idr where !fxRates.hasIdr:
            return .usd
        case .sgd where !fxRates.hasSgd:
            return .usd
        default:
            return currency
        }
    }

    private func cashValueToUSD(_ amount: Double, code: String, fxRates: PortfolioFxRates) -> Double? {
        switch code {
        case "IDR" where fxRates.hasIdr:
            return amount / fxRates.idrPerUsd!
        case "IDR":
            return nil
        case "SGD" where fxRates.hasSgd:
            return amount / fxRates.sgdPerUsd!
        case "SGD":
            return nil
        default:
            return amount
        }
    }

    private func cashNativeValue(_ holding: PortfolioHolding, _ fxRates: PortfolioFxRates) -> Double? {
        guard holding.isCash else { return nil }
        if let nativeAmount = holding.nativeAmount {
            return nativeAmount
        }
        let usdValue = holding.averagePrice * holding.quantity
        switch holding.cashCurrency {
        case "IDR"? where fxRates.hasIdr:
            return usdValue * fxRates.idrPerUsd!
        case "SGD"? where fxRates.hasSgd:
            return usdValue * fxRates.sgdPerUsd!
        default:
            return usdValue
        }
    }

    // MARK: - Helpers

    private func quoteSymbols(_ holdings: [PortfolioHolding]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for holding in holdings where !holding.isCash {
            if seen.insert(holding.symbol).inserted {
                result.append(holding.symbol)
            }
        }
        return result
    }

    private func cleanUpper(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (text == nil || text!.isEmpty) ? nil : text
    }

    private func cleanAssetType(_ assetType: String?, symbol: String) -> String? {
        let text = assetType?.trimmingCharacters(in: .whitespaces).lowercased()
        if let text, !text.isEmpty {
            return text
        }
        return symbol.hasSuffix("-USD") ? "crypto" : "stock"
    }

    private func cleanUnit(_ unit: String?, symbol: String) -> String? {
        let text = unit?.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "lot" || text == "share" {
            return text
        }
        return symbol.hasSuffix(".JK") ? "lot" : "share"
    }

    private func cleanEmoji(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespaces)
        return (text == nil || text!.isEmpty) ? PortfolioHolding.defaultCashEmoji : text!
    }

    private func microsNow() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000_000)
    }
}
