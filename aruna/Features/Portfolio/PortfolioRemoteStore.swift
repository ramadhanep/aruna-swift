import Foundation
import Supabase

/// Seam for remote (Supabase) portfolio persistence. Mirrors
/// `WatchlistRemoteStore`: a thrown error or `nil` return means "remote
/// unavailable — fall back to local"; an empty array is a legitimate value.
protocol PortfolioRemoteStore: AnyObject {
    /// Loads the signed-in user's portfolio row.
    /// - Returns: `nil` when there is no signed-in user to own the row, or the
    ///   entries array (possibly empty) when the row exists.
    func loadEntries() async throws -> [PortfolioHolding]?
    /// Upserts the whole portfolio as one JSON document for the signed-in user.
    func upsertEntries(_ entries: [PortfolioHolding]) async throws
}

/// Supabase-backed remote store: one `portfolios` row (`user_id`, `entries`,
/// `updated_at`) per user. Same contract as Flutter `_loadRemote`/`_saveRemote`.
@MainActor
final class SupabasePortfolioRemoteStore: PortfolioRemoteStore {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    private var userID: String? {
        client.auth.currentUser?.id.uuidString
    }

    private struct PortfolioRow: Encodable {
        let userID: String
        let entries: [PortfolioHolding]
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case entries
            case updatedAt = "updated_at"
        }
    }

    func loadEntries() async throws -> [PortfolioHolding]? {
        guard let userID else { return nil }
        let response: PostgrestResponse<AnyJSON> = try await client
            .from("portfolios")
            .select("entries")
            .eq("user_id", value: userID)
            .maybeSingle()
            .execute()
        guard let entries = response.value.objectValue?["entries"]?.arrayValue else {
            return []
        }
        return entries.compactMap { entry -> PortfolioHolding? in
            guard case .object(let object) = entry else { return nil }
            return PortfolioHolding(json: object.mapValues { $0.value })
        }
    }

    func upsertEntries(_ entries: [PortfolioHolding]) async throws {
        guard let userID else { return }
        let row = PortfolioRow(
            userID: userID,
            entries: entries,
            updatedAt: ArunaDate.isoString(from: Date())
        )
        try await client.from("portfolios").upsert(row).execute()
    }
}
