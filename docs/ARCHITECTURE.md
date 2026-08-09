# Architecture

Native Swift/SwiftUI port of the Flutter app. Every layer mirrors a Flutter
counterpart so behavior stays 1:1. When in doubt, the Flutter implementation in
`../aruna_app/lib/**` and `../aruna_app/AGENTS.md` is the source of truth.

## Layer flow

```text
SwiftUI view (Features/)
  -> controller / view model (@Observable)
  -> AppEnvironment (dependency container, @MainActor)
  -> Repository (Core/)
  -> APIClient / Supabase / ArunaStorage
  -> https://aruna.rdyy.me/api | supabase | UserDefaults
```

## App / AppEnvironment

`App/ArunaApp.swift` — `@main` entry. On launch with `-uitest-reset` it wipes
persisted settings (UI-test isolation). `RootView` is an auth gate rendering one
of: loading, `MainShell` (signed in / guest), or `SignInView` (signed out).

`App/AppEnvironment.swift` — `@MainActor @Observable` dependency container
injected into the view hierarchy via `.environment(environment)`. Owns:

- collaborators: `APIClient`, `MarketRepository`, `ArunaStorage`,
  `AuthService`, `WatchlistRepository`
- settings: `themeMode`, `privacyCensorEnabled` (persisted via `ArunaStorage`)
- boot state machine: `StartupState` (`starting`, `readyLocal`,
  `resolvingSession`, `authenticated`, `unauthenticated`) → `AuthState`
  (`loading`, `signedIn`, `guest`, `signedOut`)
- explicit `start()`: never blocks on network — unconfigured Supabase resolves
  to local/guest mode without a single await. Session restore is a local read.
- auth transitions: `signInWithGoogle()`, `continueAsGuest()`, `signOut()`,
  `handleOpenURL()` for the `aruna://` deep-link PKCE callback.

## Core

### API (`Core/API/`)

- `APIClient.swift` — `URLSession` + async/await, no HTTP lib. `get`/`post`
  against `AppConfig.baseURL`. Market endpoints send **no** Authorization
  header. Response decoding: empty body OK; non-2xx throws `APIError`; a `{"payload": ...}`
  wrapper is transparently decoded via `SecurePayload`.
- `SecurePayload.swift` — exact port of Flutter XOR/base64 decode (see
  `docs/API_CONTRACT.md`). Fails cleanly (`nil`) on any invalid input.
- `MarketRepository.swift` — quotes, symbol search, price series,
  fundamentals, latest finance price. Port of Flutter `MarketRepository`.
- `MarketModels.swift` — `StockQuote`, `SymbolSearchResult`, `PricePoint`,
  `FundamentalsSummary` (Dart-compatible JSON decoding).

### Auth (`Core/Auth/AuthService.swift`)

`protocol AuthService` — seam keeping the Supabase SDK out of views/controllers.
`SupabaseAuthService` implements it: PKCE + Google OAuth via
`ASWebAuthenticationSession`, auto-refresh, session persistence, `authStateChanges`
AsyncStream, and the Supabase-backed watchlist remote store. When Supabase is
unconfigured, `isConfigured == false` and the app runs local/guest only.

### Storage (`Core/Storage/`)

- `ArunaStorage.swift` — thin `UserDefaults` wrapper; keys centralized in
  `Key` (e.g. `aruna.watchlist.v1`). JSON store uses Dart-compatible ISO-8601
  dates so Flutter ↔ Swift persistence stays interoperable.
- `ArunaDate.swift` — date helpers.

### Components & Formatting

- `Core/Components/` — reusable views: `ArunaScaffold`, `ArunaCard`,
  `DonutChart`, `SparklineChart`, `PriceChangeText`, `TickerAvatar`,
  `StateViews`, `InlineButtonSpinner`, `ArunaListGroup`.
- `Core/Formatting/` — `ArunaFormatters` (money/number/percent/signed),
  `PrivacyFormatters` (censor-aware).

## Features

- `Home/MainShell.swift` — 3-tab root (Portfolio / Watchlist / Account).
- `SignIn/SignInView.swift` — Google OAuth + "Use local mode" guest entry.
- `Watchlist/` — list screen + view model, add-symbol sheet, repository,
  remote store. Port of the Flutter watchlist feature.
- `Account/AccountView.swift` — theme, privacy censor, sign out.

## Watchlist data flow (reference)

`WatchlistRepository` is local-first (source of truth = UserDefaults):

1. signed-in load: pull remote (Supabase) first, cache locally;
2. on remote failure: fall back to local;
3. empty local store: seed the 8 default symbols (`WatchlistItem.defaultSymbols`)
   and persist;
4. every mutation: normalize → dedupe → reindex 1-based `order` → save local →
   best-effort remote upsert (remote failure never rolls back local).

Test/deterministic seams: `WatchlistLoadOverride` (`.forceEmpty`, `.forceFailure`)
and `WatchlistRemoteStore` protocol (throws/nil = "remote unavailable").

## Flutter-parity rules

- UI renders state; controllers own async actions; repositories own storage/API.
- Models are typed; no raw `http`/Supabase/`UserDefaults` in views.
- Persistence keys and the remote API contract must stay byte-compatible with
  Flutter.
