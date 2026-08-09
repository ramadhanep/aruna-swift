import Foundation
import Observation

/// Port of Flutter `WatchlistController`
/// (`lib/features/watchlist/presentation/watchlist_controller.dart`).
///
/// Owns async actions; renders state. Local-first: symbols always load even
/// when quote fetching fails — a quote failure surfaces as a `quoteError`
/// warning, never as a screen-blocking failure.
@MainActor
@Observable
final class WatchlistViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var items: [WatchlistItem] = []
    private(set) var quotes: [String: StockQuote] = [:]
    private(set) var quoteError: String?

    let repository: WatchlistRepository
    let market: MarketRepository

    init(repository: WatchlistRepository, market: MarketRepository) {
        self.repository = repository
        self.market = market
    }

    /// Initial load: repository (seed if needed) → quotes → render. Quote
    /// failure must not block the loaded state.
    func load() async {
        phase = .loading
        do {
            items = try await repository.load()
            await refreshQuotes()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Pull-to-refresh: refresh quotes only. Never destroys the persisted
    /// watchlist; on failure the saved symbols stay and a warning is shown.
    func refreshQuotes() async {
        let symbols = items.map(\.symbol)
        guard !symbols.isEmpty else { return }
        do {
            quotes = try await market.fetchQuotes(symbols)
            quoteError = nil
        } catch {
            // Keep previously fetched quotes; surface the warning.
            quoteError = String(describing: error)
        }
    }

    /// Exact-symbol add (also used by search results). Returns `false` for
    /// empty input or an existing symbol (no duplicate, order preserved).
    @discardableResult
    func addSymbol(_ symbol: String, name: String? = nil) async throws -> Bool {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return false }
        guard !items.contains(where: { $0.symbol == normalized }) else { return false }
        items = try await repository.save([WatchlistItem(symbol: normalized, name: name)] + items)
        await refreshQuotes()
        return true
    }

    func removeSymbol(_ symbol: String) async throws {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let next = items.filter { $0.symbol != normalized }
        items = try await repository.save(next)
        quotes.removeValue(forKey: normalized)
    }

    func reorderSymbol(from dragged: String, to target: String) async {
        guard let oldIndex = items.firstIndex(where: { $0.symbol == dragged }),
              let newIndex = items.firstIndex(where: { $0.symbol == target }),
              oldIndex != newIndex else { return }
        var next = items
        let moved = next.remove(at: oldIndex)
        next.insert(moved, at: newIndex)
        do {
            items = try await repository.save(next)
        } catch {
            // Reorder must not crash or roll back the display on sync failure.
        }
    }

    func searchSymbols(_ query: String) async throws -> [SymbolSearchResult] {
        try await market.searchSymbols(query)
    }
}
