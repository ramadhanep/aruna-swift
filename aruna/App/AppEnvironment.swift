import Foundation
import Observation
import SwiftUI

/// Explicit boot/auth state. One state per meaningful startup outcome so the
/// root view can never be stuck behind an ambiguous `isLoading` boolean.
enum StartupState {
    case starting
    case readyLocal
    case resolvingSession
    case authenticated
    case unauthenticated
}

/// Terminal auth state the root gate renders on.
enum AuthState: Equatable {
    case loading
    case signedIn
    case guest
    case signedOut
}

/// Dependency container injected into the view hierarchy. Feature controllers
/// read their collaborators from here instead of constructing them directly.
@MainActor
@Observable
final class AppEnvironment {
    let apiClient: APIClient
    let marketRepository: MarketRepository
    let storage: ArunaStorage
    let authService: any AuthService
    let watchlistRepository: WatchlistRepository
    let portfolioRepository: PortfolioRepository

    var themeMode: ArunaThemeMode {
        didSet { storage.set(themeMode.rawValue, forKey: ArunaStorage.Key.themeMode) }
    }

    var privacyCensorEnabled: Bool {
        didSet { storage.set(privacyCensorEnabled, forKey: ArunaStorage.Key.privacyCensorEnabled) }
    }

    private(set) var pendingURL: URL?
    private(set) var startupState: StartupState = .starting
    /// Local-mode override mirroring Flutter `AuthSnapshot.isGuest`.
    private(set) var isGuest = false
    private var authObservationTask: Task<Void, Never>?

    init(
        apiClient: APIClient,
        storage: ArunaStorage,
        authService: (any AuthService)? = nil,
        watchlistLoadOverride: WatchlistLoadOverride = .normal,
        portfolioLoadOverride: PortfolioLoadOverride = .normal
    ) {
        self.apiClient = apiClient
        self.marketRepository = MarketRepository(apiClient: apiClient)
        self.storage = storage
        self.authService = authService ?? SupabaseAuthService()
        self.themeMode = ArunaThemeMode(rawValue: storage.string(forKey: ArunaStorage.Key.themeMode) ?? "") ?? .dark
        self.privacyCensorEnabled = storage.bool(forKey: ArunaStorage.Key.privacyCensorEnabled)
        self.watchlistRepository = WatchlistRepository(
            storage: storage,
            remoteStore: self.authService.watchlistRemoteStore,
            loadOverride: watchlistLoadOverride
        )
        self.portfolioRepository = PortfolioRepository(
            storage: storage,
            remoteStore: self.authService.portfolioRemoteStore,
            loadOverride: portfolioLoadOverride
        )
    }

    // MARK: - Startup

    /// Explicit async startup. Never blocks the UI or the network for boot:
    /// unconfigured Supabase resolves to local mode without a single await.
    func start() async {
        guard authService.isConfigured else {
            startupState = .readyLocal
            return
        }
        startupState = .resolvingSession
        do {
            startupState = try await authService.restoreSession() ? .authenticated : .unauthenticated
        } catch {
            // Session/network hiccup must not leave an infinite spinner;
            // fall back to the signed-out state (local-first parity).
            startupState = .unauthenticated
        }
        observeAuthState()
    }

    private func observeAuthState() {
        guard authObservationTask == nil else { return }
        authObservationTask = Task { [weak self] in
            guard let self else { return }
            for await signedIn in self.authService.authStateChanges {
                self.applyAuthChange(signedIn)
            }
        }
    }

    private func applyAuthChange(_ signedIn: Bool) {
        if signedIn {
            isGuest = false
            startupState = .authenticated
        } else {
            isGuest = false
            startupState = authService.isConfigured ? .unauthenticated : .readyLocal
        }
    }

    static func live() -> AppEnvironment {
        let configuration = UITestSupport.configuration
        let session = configuration == .mockAPI ? UITestSupport.mockSession() : .shared
        return AppEnvironment(
            apiClient: APIClient(
                baseURL: AppConfig.baseURL,
                payloadKey: AppConfig.securePayloadKey,
                session: session
            ),
            storage: ArunaStorage(),
            watchlistLoadOverride: configuration.watchlistOverride,
            portfolioLoadOverride: configuration.portfolioOverride
        )
    }

    // MARK: - Auth state (Flutter `AuthSnapshot` parity)

    var isSupabaseConfigured: Bool { authService.isConfigured }

    var currentUser: AuthUser? { authService.currentUser }

    var isSignedIn: Bool { authState == .signedIn }

    var canEnterApp: Bool {
        // Flutter contract: `canEnterApp = isSignedIn || isGuest`.
        authState == .signedIn || authState == .guest
    }

    var authState: AuthState {
        switch startupState {
        case .starting, .resolvingSession:
            return .loading
        case .readyLocal:
            return .guest
        case .authenticated:
            return .signedIn
        case .unauthenticated:
            return isGuest ? .guest : .signedOut
        }
    }

    /// `Use local mode` — sets guest state, no network, no Supabase.
    func continueAsGuest() {
        isGuest = true
    }

    func signInWithGoogle() async throws {
        let signedIn = try await authService.signInWithGoogle()
        if signedIn {
            isGuest = false
            startupState = .authenticated
        }
    }

    func signOut() async throws {
        try await authService.signOut()
        // Flutter parity: after sign-out, configured -> signed out (gate ->
        // SignInView); unconfigured -> local mode.
        isGuest = false
        startupState = authService.isConfigured ? .unauthenticated : .readyLocal
    }

    // MARK: - Settings

    func togglePrivacyCensor() {
        privacyCensorEnabled.toggle()
    }

    // MARK: - Deep link

    func handleOpenURL(_ url: URL) {
        pendingURL = url
        authService.handleOpenURL(url)
    }

    func palette(for colorScheme: ColorScheme) -> ArunaPalette {
        themeMode.palette(for: colorScheme)
    }
}
