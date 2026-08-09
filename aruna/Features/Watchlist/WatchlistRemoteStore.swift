import Foundation
import Supabase

/// Seam for remote (Supabase) watchlist persistence. The repository treats a
/// thrown error or a returned `nil` as "remote unavailable — fall back to
/// local"; an empty array is a legitimate remote value.
protocol WatchlistRemoteStore: AnyObject {
    /// Loads the signed-in user's watchlist row.
    /// - Returns: `nil` when there is no signed-in user to own the row, or the
    ///   items array (possibly empty) when the row exists.
    func loadItems() async throws -> [WatchlistItem]?
    /// Upserts the whole watchlist as one JSON document for the signed-in user.
    func upsertItems(_ items: [WatchlistItem]) async throws
}

/// Supabase-backed remote store: one `watchlists` row (`user_id`, `items`,
/// `updated_at`) per user. Same contract as Flutter `_loadRemote`/`_saveRemote`.
@MainActor
final class SupabaseWatchlistRemoteStore: WatchlistRemoteStore {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    private var userID: String? {
        client.auth.currentUser?.id.uuidString
    }

    private struct WatchlistRow: Encodable {
        let userID: String
        let items: [WatchlistItem]
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case items
            case updatedAt = "updated_at"
        }
    }

    func loadItems() async throws -> [WatchlistItem]? {
        guard let userID else { return nil }
        let response: PostgrestResponse<AnyJSON> = try await client
            .from("watchlists")
            .select("items")
            .eq("user_id", value: userID)
            .maybeSingle()
            .execute()
        guard let items = response.value.objectValue?["items"]?.arrayValue else {
            return []
        }
        return items.compactMap { entry -> WatchlistItem? in
            guard case .object(let object) = entry else { return nil }
            return WatchlistItem(json: object.mapValues { $0.value })
        }
    }

    func upsertItems(_ items: [WatchlistItem]) async throws {
        guard let userID else { return }
        let row = WatchlistRow(
            userID: userID,
            items: items,
            updatedAt: ArunaDate.isoString(from: Date())
        )
        try await client.from("watchlists").upsert(row).execute()
    }
}
