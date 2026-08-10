import Foundation
import Supabase

/// Public view of the signed-in identity. Keeps Supabase's `User` type out of
/// views and controllers.
struct AuthUser: Equatable {
    let name: String?
    let email: String?
}

/// Clean seam so the rest of the app never depends on the Supabase SDK
/// directly.
protocol AuthService: AnyObject {
    /// True when real Supabase credentials are present. When false the app
    /// must enter local/guest mode without touching the SDK.
    var isConfigured: Bool { get }
    /// The signed-in user, if any.
    var currentUser: AuthUser? { get }
    /// Restores a persisted session. Local storage read only — never blocks
    /// on the network. Returns true when a session exists.
    func restoreSession() async throws -> Bool
    /// Starts Google OAuth (PKCE via `ASWebAuthenticationSession`). Returns
    /// true when a session was established.
    func signInWithGoogle() async throws -> Bool
    /// Signs out the current session.
    func signOut() async throws
    func handleOpenURL(_ url: URL)
    /// Emits `true` on signed-in and `false` on signed-out transitions.
    var authStateChanges: AsyncStream<Bool> { get }
    /// Supabase-backed watchlist remote persistence, or `nil` when Supabase is
    /// unconfigured (local/guest mode uses local persistence only).
    var watchlistRemoteStore: (any WatchlistRemoteStore)? { get }
    /// Supabase-backed portfolio remote persistence, or `nil` when Supabase is
    /// unconfigured (local/guest mode uses local persistence only).
    var portfolioRemoteStore: (any PortfolioRemoteStore)? { get }
}

@MainActor
final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    var currentUser: AuthUser? {
        guard let user = client?.auth.currentUser else { return nil }
        let name = user.userMetadata["full_name"]?.stringValue
            ?? user.userMetadata["name"]?.stringValue
        return AuthUser(name: name, email: user.email)
    }

    init(client: SupabaseClient? = nil) {
        self.client = client ?? Self.makeClient()
        self.watchlistRemoteStore = self.client.map { SupabaseWatchlistRemoteStore(client: $0) }
        self.portfolioRemoteStore = self.client.map { SupabasePortfolioRemoteStore(client: $0) }
    }

    /// Supabase-backed remote persistence, or `nil` when no client is present
    /// (local/guest mode).
    let watchlistRemoteStore: (any WatchlistRemoteStore)?
    /// Supabase-backed portfolio remote persistence, or `nil` when no client is
    /// present (local/guest mode).
    let portfolioRemoteStore: (any PortfolioRemoteStore)?

    /// PKCE + auto-refresh + session persistence are configured at client
    /// creation. Session persistence uses the SDK's default local storage.
    private static func makeClient() -> SupabaseClient? {
        guard AppConfig.isSupabaseConfigured,
              let url = URL(string: AppConfig.supabaseURL),
              !AppConfig.supabaseAnonKey.isEmpty else {
            return nil
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: AppConfig.oauthRedirectURL),
                    flowType: .pkce,
                    autoRefreshToken: true
                )
            )
        )
    }

    /// Reads the SDK-persisted session synchronously (no network). Live
    /// session refresh keeps running in the background via autoRefreshToken.
    func restoreSession() async throws -> Bool {
        guard let client else { return false }
        return client.auth.currentSession != nil
    }

    /// Google OAuth via the SDK's `ASWebAuthenticationSession` PKCE flow. The
    /// callback scheme (`aruna`) must be registered; the returned session is
    /// persisted by the SDK and also emitted through `authStateChanges`.
    func signInWithGoogle() async throws -> Bool {
        guard let client else { return false }
        _ = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: AppConfig.oauthRedirectURL)
        )
        return true
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut()
    }

    /// Forwards a deep-link callback (`aruna://login-callback/...`) to the
    /// SDK so PKCE sessions restore on cold start.
    func handleOpenURL(_ url: URL) {
        client?.handle(url)
    }

    var authStateChanges: AsyncStream<Bool> {
        guard let client else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            Task {
                for await change in client.auth.authStateChanges {
                    switch change.event {
                    case .signedIn:
                        continuation.yield(true)
                    case .signedOut:
                        continuation.yield(false)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
        }
    }
}
