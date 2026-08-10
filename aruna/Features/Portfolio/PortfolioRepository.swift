import Foundation

/// Test/deterministic seam for `load()`. `.normal` reproduces Flutter's
/// local-first semantics exactly; the force cases are only used by unit and UI
/// tests to exercise the error/empty rendering paths deterministically.
enum PortfolioLoadOverride: Equatable {
    case normal
    case forceEmpty
    case forceFailure
}

enum PortfolioRepositoryError: Error {
    case loadFailed
}

/// Port of Flutter `PortfolioRepository`
/// (`lib/features/portfolio/data/portfolio_repository.dart`).
///
/// Local-first semantics: signed-in load pulls remote first and caches it
/// locally; on remote failure it falls back to local; a missing remote and an
/// empty local store return an empty portfolio (no seed). Every mutation
/// filters invalid holdings (empty symbol, `quantity <= 0`, `averagePrice < 0`),
/// saves locally, then best-effort remote upserts (local is the source of
/// truth; remote failures never roll back local).
struct PortfolioRepository {
    static let localKey = ArunaStorage.Key.portfolio
    static let sortKey = ArunaStorage.Key.portfolioSort
    static let currencyKey = ArunaStorage.Key.portfolioCurrency

    let storage: ArunaStorage
    let remoteStore: (any PortfolioRemoteStore)?
    let loadOverride: PortfolioLoadOverride

    init(
        storage: ArunaStorage,
        remoteStore: (any PortfolioRemoteStore)? = nil,
        loadOverride: PortfolioLoadOverride = .normal
    ) {
        self.storage = storage
        self.remoteStore = remoteStore
        self.loadOverride = loadOverride
    }

    // MARK: - Load

    func load() async throws -> [PortfolioHolding] {
        if loadOverride == .forceEmpty { return [] }
        if loadOverride == .forceFailure { throw PortfolioRepositoryError.loadFailed }

        if let remoteStore,
           let remote = try? await remoteStore.loadEntries() {
            let cleaned = remote.filter { !$0.symbol.isEmpty }
            try saveLocal(cleaned)
            return cleaned
        }
        return loadLocal()
    }

    // MARK: - Save

    @discardableResult
    func save(_ holdings: [PortfolioHolding]) async throws -> [PortfolioHolding] {
        let cleaned = holdings.filter(valid)
        try saveLocal(cleaned)
        // Best-effort remote sync: local storage remains the source of truth
        // when Supabase is unavailable (Flutter `_saveRemote` swallows errors).
        try? await remoteStore?.upsertEntries(cleaned)
        return cleaned
    }

    // MARK: - Sort preference

    func loadSortOption() -> PortfolioSortOption {
        let raw = storage.string(forKey: Self.sortKey)
        return PortfolioSortOption(rawValue: raw ?? "") ?? .symbol
    }

    func saveSortOption(_ option: PortfolioSortOption) {
        storage.set(option.rawValue, forKey: Self.sortKey)
    }

    // MARK: - Display currency preference

    func loadDisplayCurrency() -> PortfolioDisplayCurrency {
        let raw = storage.string(forKey: Self.currencyKey)?.lowercased()
        return PortfolioDisplayCurrency(rawValue: raw ?? "") ?? .idr
    }

    func saveDisplayCurrency(_ currency: PortfolioDisplayCurrency) {
        storage.set(currency.code, forKey: Self.currencyKey)
    }

    // MARK: - Local persistence

    private func saveLocal(_ holdings: [PortfolioHolding]) throws {
        try storage.setJSON(holdings, forKey: Self.localKey)
    }

    private func loadLocal() -> [PortfolioHolding] {
        guard let stored = try? storage.jsonObject([PortfolioHolding].self, forKey: Self.localKey) else {
            return []
        }
        return stored.filter { !$0.symbol.isEmpty }
    }

    /// Flutter validation: drop holdings with an empty symbol, `quantity <= 0`,
    /// or `averagePrice < 0`.
    private func valid(_ holding: PortfolioHolding) -> Bool {
        !holding.symbol.isEmpty && holding.quantity > 0 && holding.averagePrice >= 0
    }
}
