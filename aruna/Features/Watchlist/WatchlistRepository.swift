import Foundation

/// Test/deterministic seam for `load()`. `.normal` reproduces Flutter's
/// local-first semantics exactly; the force cases are only used by unit and UI
/// tests to exercise the error/empty rendering paths that real data cannot
/// reach deterministically.
enum WatchlistLoadOverride: Equatable {
    case normal
    case forceEmpty
    case forceFailure
}

enum WatchlistRepositoryError: Error {
    case loadFailed
}

/// Port of Flutter `WatchlistRepository`
/// (`lib/features/watchlist/data/watchlist_repository.dart`).
///
/// Local-first semantics: signed-in load pulls remote first and caches it
/// locally; on remote failure it falls back to local; an empty local store
/// seeds the 8 default symbols and persists them. Every mutation normalizes →
/// dedupes → reindexes `order` → saves locally → best-effort remote upsert
/// (local is the source of truth; remote failures never roll back local).
struct WatchlistRepository {
    static let localKey = ArunaStorage.Key.watchlist

    let storage: ArunaStorage
    let remoteStore: (any WatchlistRemoteStore)?
    let loadOverride: WatchlistLoadOverride

    init(
        storage: ArunaStorage,
        remoteStore: (any WatchlistRemoteStore)? = nil,
        loadOverride: WatchlistLoadOverride = .normal
    ) {
        self.storage = storage
        self.remoteStore = remoteStore
        self.loadOverride = loadOverride
    }

    // MARK: - Load

    func load() async throws -> [WatchlistItem] {
        if loadOverride == .forceEmpty { return [] }
        if loadOverride == .forceFailure { throw WatchlistRepositoryError.loadFailed }

        if let remoteStore,
           let remote = try? await remoteStore.loadItems() {
            let cleaned = ordered(dedupe(remote.filter { !$0.symbol.isEmpty }))
            try saveLocal(cleaned)
            return cleaned
        }

        let local = loadLocal()
        if !local.isEmpty { return local }

        let seeded = seed()
        _ = try await save(seeded)
        return seeded
    }

    // MARK: - Save

    @discardableResult
    func save(_ items: [WatchlistItem]) async throws -> [WatchlistItem] {
        let cleaned = dedupe(items)
        try saveLocal(cleaned)
        // Best-effort remote sync: local storage remains the source of truth
        // when Supabase is unavailable (Flutter `_saveRemote` swallows errors).
        try? await remoteStore?.upsertItems(cleaned)
        return cleaned
    }

    // MARK: - Local persistence

    private func saveLocal(_ items: [WatchlistItem]) throws {
        try storage.setJSON(items, forKey: Self.localKey)
    }

    private func loadLocal() -> [WatchlistItem] {
        guard let stored = try? storage.jsonObject([WatchlistItem].self, forKey: Self.localKey) else {
            return []
        }
        return ordered(dedupe(stored.filter { !$0.symbol.isEmpty }))
    }

    // MARK: - Normalization / dedupe / order

    /// Flutter `_dedupe`: trims + uppercases, keeps the first logical item,
    /// drops empties/duplicates, and reindexes `order` 1-based.
    func dedupe(_ items: [WatchlistItem]) -> [WatchlistItem] {
        var seen = Set<String>()
        var result: [WatchlistItem] = []
        for item in items {
            let symbol = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if symbol.isEmpty || !seen.insert(symbol).inserted { continue }
            result.append(
                WatchlistItem(symbol: symbol, name: item.name, order: result.count + 1, addedAt: item.addedAt)
            )
        }
        return result
    }

    /// Flutter `_ordered`: sort by `order` (missing → large value), then `addedAt`.
    func ordered(_ items: [WatchlistItem]) -> [WatchlistItem] {
        guard items.contains(where: { $0.order != nil }) else { return items }
        return items.sorted {
            let lhs = $0.order ?? (1 << 30)
            let rhs = $1.order ?? (1 << 30)
            if lhs != rhs { return lhs < rhs }
            return $0.addedAt < $1.addedAt
        }
    }

    /// Flutter seed: defaults in exact order, 1-based `order`, `addedAt = now`.
    func seed() -> [WatchlistItem] {
        WatchlistItem.defaultSymbols.enumerated().map { index, symbol in
            WatchlistItem(symbol: symbol, order: index + 1)
        }
    }
}
