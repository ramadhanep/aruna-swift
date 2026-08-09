import Foundation

/// Compile-time / runtime configuration.
///
/// Values are resolved from (in order): the process environment, then the app
/// Info.plist (populated by `Config/Config.xcconfig` build settings). Real
/// secrets must be supplied locally via `Config/Config.xcconfig` or an
/// environment variable — never hardcoded in source.
enum AppConfig {
    static let apiBaseURL: String =
        configured("ARUNA_API_BASE_URL") ?? "https://arunaa.vercel.app/api"

    static let supabaseURL: String =
        configured("SUPABASE_URL")
        ?? configured("NEXT_PUBLIC_SUPABASE_URL")
        ?? "https://<your-project>.supabase.co"

    static let supabaseAnonKey: String =
        configured("SUPABASE_ANON_KEY")
        ?? configured("NEXT_PUBLIC_SUPABASE_ANON_KEY")
        ?? "<your-anon-key>"

    static let securePayloadKey: String =
        configured("ARUNA_SECURE_PAYLOAD_KEY")
        ?? configured("SECURE_PAYLOAD_KEY")
        ?? "change-me-to-something-random"

    static let oauthRedirectURL: String = {
        let value =
            (configured("ARUNA_OAUTH_REDIRECT_URL") ?? "aruna://login-callback/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "aruna://login-callback" ? "aruna://login-callback/" : value
    }()

    /// Mirrors Flutter `AppConfig.isSupabaseConfigured`.
    static var isSupabaseConfigured: Bool {
        supabaseURL.hasPrefix("https://")
            && !supabaseURL.contains("<your-project>")
            && !supabaseAnonKey.isEmpty
            && !supabaseAnonKey.contains("<your-anon-key>")
    }

    static var baseURL: URL {
        URL(string: apiBaseURL) ?? URL(string: "https://arunaa.vercel.app/api")!
    }

    private static func configured(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key],
           !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        return value.isEmpty ? nil : value
    }
}
