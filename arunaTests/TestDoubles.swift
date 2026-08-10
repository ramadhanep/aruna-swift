//
//  TestDoubles.swift
//  arunaTests
//
//  Shared auth test double. Never touches Supabase.
//

import Foundation
@testable import aruna

enum TestError: Error {
    case restoreFailed
    case signOutFailed
}

@MainActor
final class MockAuthService: AuthService {
    let isConfigured: Bool
    var hasSession: Bool
    var restoreError: Error?
    var signInResult: Bool
    var signOutError: Error?
    var currentUser: AuthUser?
    var watchlistRemoteStore: (any WatchlistRemoteStore)?
    var portfolioRemoteStore: (any PortfolioRemoteStore)?

    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    init(
        isConfigured: Bool,
        hasSession: Bool = false,
        restoreError: Error? = nil,
        signInResult: Bool = true,
        signOutError: Error? = nil,
        currentUser: AuthUser? = nil,
        watchlistRemoteStore: (any WatchlistRemoteStore)? = nil,
        portfolioRemoteStore: (any PortfolioRemoteStore)? = nil
    ) {
        self.isConfigured = isConfigured
        self.hasSession = hasSession
        self.restoreError = restoreError
        self.signInResult = signInResult
        self.signOutError = signOutError
        self.currentUser = currentUser
        self.watchlistRemoteStore = watchlistRemoteStore
        self.portfolioRemoteStore = portfolioRemoteStore
        (self.stream, self.continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    var authStateChanges: AsyncStream<Bool> { stream }

    func restoreSession() async throws -> Bool {
        if let restoreError { throw restoreError }
        return hasSession
    }

    func signInWithGoogle() async throws -> Bool {
        if signInResult { hasSession = true }
        return signInResult
    }

    func signOut() async throws {
        if let signOutError { throw signOutError }
        hasSession = false
        continuation.yield(false)
    }

    /// Simulates a deep-link callback (`aruna://login-callback/`) restoring a
    /// session.
    func handleOpenURL(_ url: URL) {
        guard url.host == "login-callback" else { return }
        hasSession = true
        continuation.yield(true)
    }

    /// Manually emits an auth-state change to drive the environment's listener.
    func emit(_ signedIn: Bool) {
        continuation.yield(signedIn)
    }
}

/// Deterministic remote-store double. `itemsToReturn = nil` means "no remote
/// data" (local fallback); `loadError` simulates a Supabase failure.
@MainActor
final class MockWatchlistRemoteStore: WatchlistRemoteStore {
    var itemsToReturn: [WatchlistItem]?
    var loadError: Error?
    var upsertError: Error?
    private(set) var upsertedItems: [WatchlistItem]?
    private(set) var upsertCallCount = 0

    func loadItems() async throws -> [WatchlistItem]? {
        if let loadError { throw loadError }
        return itemsToReturn
    }

    func upsertItems(_ items: [WatchlistItem]) async throws {
        upsertCallCount += 1
        if let upsertError { throw upsertError }
        upsertedItems = items
    }
}

/// Deterministic portfolio remote-store double. `entriesToReturn = nil` means
/// "no remote data" (local fallback); `loadError` simulates a Supabase failure.
@MainActor
final class MockPortfolioRemoteStore: PortfolioRemoteStore {
    var entriesToReturn: [PortfolioHolding]?
    var loadError: Error?
    var upsertError: Error?
    private(set) var upsertedEntries: [PortfolioHolding]?
    private(set) var upsertCallCount = 0

    func loadEntries() async throws -> [PortfolioHolding]? {
        if let loadError { throw loadError }
        return entriesToReturn
    }

    func upsertEntries(_ entries: [PortfolioHolding]) async throws {
        upsertCallCount += 1
        if let upsertError { throw upsertError }
        upsertedEntries = entries
    }
}
