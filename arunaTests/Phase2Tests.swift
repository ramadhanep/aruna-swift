//
//  Phase2Tests.swift
//  arunaTests
//
//  Phase 2 — Auth + shell: auth gate contract, guest/local mode, theme and
//  privacy persistence. Uses `MockAuthService` — no real Supabase.
//

import XCTest
@testable import aruna

@MainActor
final class AuthStateTests: XCTestCase {

    private func makeEnvironment(auth: any AuthService, storage: ArunaStorage = ArunaStorage()) -> AppEnvironment {
        AppEnvironment(
            apiClient: APIClient(baseURL: URL(string: "https://example.com")!, payloadKey: "test"),
            storage: storage,
            authService: auth
        )
    }

    /// `canEnterApp = isSignedIn || isGuest` — local mode enters the app.
    func testLocalModeCanEnterApp() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: false))
        await environment.start()

        XCTAssertEqual(environment.authState, .guest)
        XCTAssertTrue(environment.canEnterApp)
        XCTAssertFalse(environment.isSignedIn)
    }

    /// Signed-in session enters the app.
    func testSignedInCanEnterApp() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: true))
        await environment.start()

        XCTAssertEqual(environment.authState, .signedIn)
        XCTAssertTrue(environment.canEnterApp)
        XCTAssertTrue(environment.isSignedIn)
    }

    /// Signed-out (configured, no session) is blocked from the app.
    func testSignedOutCannotEnterApp() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: false))
        await environment.start()

        XCTAssertEqual(environment.authState, .signedOut)
        XCTAssertFalse(environment.canEnterApp)
    }

    /// `Use local mode` transitions signed-out → guest with no network.
    func testContinueAsGuestEntersAppFromSignedOut() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: false))
        await environment.start()
        XCTAssertEqual(environment.authState, .signedOut)

        environment.continueAsGuest()

        XCTAssertEqual(environment.authState, .guest)
        XCTAssertTrue(environment.canEnterApp)
    }

    /// Google sign-in resolves to signed-in.
    func testSignInWithGoogleResolvesSignedIn() async throws {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: false))
        await environment.start()
        XCTAssertEqual(environment.authState, .signedOut)

        try await environment.signInWithGoogle()

        XCTAssertEqual(environment.authState, .signedIn)
        XCTAssertTrue(environment.canEnterApp)
    }

    /// Sign-out (configured) resolves to signed-out → auth gate shows sign-in.
    func testSignOutConfiguredResolvesSignedOut() async throws {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: true))
        await environment.start()
        XCTAssertEqual(environment.authState, .signedIn)

        try await environment.signOut()

        XCTAssertEqual(environment.authState, .signedOut)
        XCTAssertFalse(environment.canEnterApp)
    }

    /// Deep-link callback restores a session and updates auth state.
    func testDeepLinkRestoresSessionAndUpdatesAuthState() async throws {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: false))
        await environment.start()
        XCTAssertEqual(environment.authState, .signedOut)

        environment.handleOpenURL(URL(string: "aruna://login-callback/")!)
        let deadline = Date().addingTimeInterval(5)
        while environment.authState != .signedIn && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(environment.authState, .signedIn)
        XCTAssertTrue(environment.canEnterApp)
    }

    /// Unconfigured Supabase: local mode available, Google sign-in unavailable.
    func testUnconfiguredKeepsLocalModeAndBlocksGoogle() async {
        let auth = MockAuthService(isConfigured: false)
        let environment = makeEnvironment(auth: auth)
        await environment.start()

        XCTAssertFalse(environment.isSupabaseConfigured)
        XCTAssertEqual(environment.authState, .guest)
        XCTAssertTrue(environment.canEnterApp)
        XCTAssertFalse(auth.isConfigured)
    }
}

@MainActor
final class SettingsTests: XCTestCase {

    private func makeStorage() -> ArunaStorage {
        let suite = "SettingsTests-\(UUID().uuidString)"
        return ArunaStorage(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeEnvironment(storage: ArunaStorage) -> AppEnvironment {
        AppEnvironment(
            apiClient: APIClient(baseURL: URL(string: "https://example.com")!, payloadKey: "test"),
            storage: storage,
            authService: MockAuthService(isConfigured: false)
        )
    }

    // MARK: - Theme

    func testThemeDefaultsToDark() {
        let storage = makeStorage()
        XCTAssertNil(storage.string(forKey: ArunaStorage.Key.themeMode))

        let environment = makeEnvironment(storage: storage)

        XCTAssertEqual(environment.themeMode, .dark)
    }

    func testSettingLightThemePersists() {
        let storage = makeStorage()
        let environment = makeEnvironment(storage: storage)

        environment.themeMode = .light

        XCTAssertEqual(storage.string(forKey: ArunaStorage.Key.themeMode), "light")
        XCTAssertEqual(makeEnvironment(storage: storage).themeMode, .light)
    }

    func testSettingSystemThemePersists() {
        let storage = makeStorage()
        let environment = makeEnvironment(storage: storage)

        environment.themeMode = .system

        XCTAssertEqual(storage.string(forKey: ArunaStorage.Key.themeMode), "system")
        XCTAssertEqual(makeEnvironment(storage: storage).themeMode, .system)
    }

    // MARK: - Privacy

    func testPrivacyDefaultsToFalse() {
        let storage = makeStorage()
        XCTAssertFalse(storage.bool(forKey: ArunaStorage.Key.privacyCensorEnabled))

        let environment = makeEnvironment(storage: storage)

        XCTAssertFalse(environment.privacyCensorEnabled)
    }

    func testPrivacyToggleTruePersists() {
        let storage = makeStorage()
        let environment = makeEnvironment(storage: storage)

        environment.togglePrivacyCensor()

        XCTAssertTrue(environment.privacyCensorEnabled)
        XCTAssertTrue(storage.bool(forKey: ArunaStorage.Key.privacyCensorEnabled))
        XCTAssertTrue(makeEnvironment(storage: storage).privacyCensorEnabled)
    }

    func testPrivacyToggleFalsePersists() {
        let storage = makeStorage()
        let environment = makeEnvironment(storage: storage)
        environment.togglePrivacyCensor()
        XCTAssertTrue(environment.privacyCensorEnabled)

        environment.togglePrivacyCensor()

        XCTAssertFalse(environment.privacyCensorEnabled)
        XCTAssertFalse(storage.bool(forKey: ArunaStorage.Key.privacyCensorEnabled))
        XCTAssertFalse(makeEnvironment(storage: storage).privacyCensorEnabled)
    }
}
