//
//  StartupTests.swift
//  arunaTests
//
//  Regression tests for the boot fix: the root view must never stay on the
//  "Foundation ready" loading placeholder. Unconfigured Supabase resolves to
//  local mode immediately; configured auth resolves to a terminal state even
//  when session restore fails. No state may depend on a deep link.
//

import XCTest
@testable import aruna

@MainActor
final class StartupTests: XCTestCase {

    private func makeEnvironment(auth: any AuthService) -> AppEnvironment {
        AppEnvironment(
            apiClient: APIClient(baseURL: URL(string: "https://example.com")!, payloadKey: "test"),
            storage: ArunaStorage(),
            authService: auth
        )
    }

    /// Test 1 — Local mode boot: placeholder/missing Supabase config resolves
    /// immediately and never enters an infinite loading state.
    func testUnconfiguredResolvesToLocalModeImmediately() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: false))
        XCTAssertEqual(environment.startupState, .starting)

        await environment.start()

        XCTAssertEqual(environment.startupState, .readyLocal)
    }

    /// Test 2 — Configured auth boot with a valid session becomes authenticated.
    func testConfiguredWithSessionBecomesAuthenticated() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: true))

        await environment.start()

        XCTAssertEqual(environment.startupState, .authenticated)
    }

    /// Test 2b — Configured auth boot without a session becomes unauthenticated.
    func testConfiguredWithoutSessionBecomesUnauthenticated() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: true, hasSession: false))

        await environment.start()

        XCTAssertEqual(environment.startupState, .unauthenticated)
    }

    /// Test 3 — Session restore failure must not leave an infinite spinner.
    func testSessionRestoreFailureResolvesToUnauthenticated() async {
        let environment = makeEnvironment(
            auth: MockAuthService(isConfigured: true, restoreError: TestError.restoreFailed)
        )

        await environment.start()

        XCTAssertEqual(environment.startupState, .unauthenticated)
    }

    /// Test 4 — A normal launch without `aruna://login-callback/` must not wait
    /// for OAuth handling. Startup is fully independent of `handleOpenURL`.
    func testBootDoesNotRequireDeepLink() async {
        let environment = makeEnvironment(auth: MockAuthService(isConfigured: false))
        XCTAssertNil(environment.pendingURL)

        await environment.start()

        XCTAssertEqual(environment.startupState, .readyLocal)
    }
}
