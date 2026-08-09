# Aruna (iOS / SwiftUI)

Dark, dense, iOS-first companion for monitoring IDX/US/ETF/crypto watchlists,
inspecting quotes, and tracking portfolio performance.

This is the **native iOS rewrite** of the Flutter app "Aruna Lite". It ports the
Flutter behavior 1:1. Flutter source lives in the sibling repo folder
`aruna_app/`; the full migration spec and audit is in `../MIGRATION.md`.

## Repository layout

```
aruna/
  Config/
    Config.xcconfig           # local secrets — GITIGNORED, never commit
    Config.xcconfig.example   # committed template
  Supporting/Info.plist       # reads $(VARIABLE)s from xcconfig at build
  aruna/
    App/                      # entry, environment container, theme, ui-test hooks
    Core/
      API/                    # APIClient, SecurePayload, MarketRepository, models
      Auth/                   # AuthService (Supabase PKCE / guest mode)
      Components/             # shared SwiftUI views
      Formatting/             # money/percent/date + privacy censor
      Storage/                # UserDefaults wrapper, Dart-compatible dates
    Features/
      Home/                   # MainShell: 3-tab root
      SignIn/                 # Google OAuth + guest entry
      Watchlist/              # list, search, add, reorder, sync
      Account/                # settings (theme, privacy, sign out)
  arunaTests/                 # unit tests
  arunaUITests/               # UI tests (mock API via URLProtocol)
```

## Quick start

1. Open `aruna.xcodeproj` in Xcode 26+.
2. Copy `Config/Config.xcconfig.example` → `Config/Config.xcconfig` and fill in
   real values (see `docs/CONFIGURATION.md`). Placeholders work for local-only
   (guest) mode.
3. Build & run. Without Supabase credentials the app boots straight into guest
   mode — no network, no login required.

## Config & secrets

- All runtime config flows: process environment → Info.plist → default.
- Real keys are **never** committed. `Config/Config.xcconfig` is gitignored;
  the committed file is `Config.xcconfig.example` with placeholders.
- See `docs/CONFIGURATION.md` for the full key list and resolution order.

## Tests

- Unit: `arunaTests/` — run via `Product > Test` (⌘U) or `xcodebuild test`.
- UI: `arunaUITests/` — offline deterministic API served by
  `UITestURLProtocol`; launch-arg flags: `-uitest-api-mock`,
  `-uitest-watchlist-empty`, `-uitest-watchlist-fail`,
  `UITEST_API_MODE` env for scenarios. See `docs/TESTING.md`.

## Docs (read these first)

- `docs/ARCHITECTURE.md` — layers, dependency flow, Flutter-parity rules
- `docs/CONFIGURATION.md` — config keys, secrets policy, Info.plist wiring
- `docs/API_CONTRACT.md` — REST endpoints, secure payload algorithm, errors
- `docs/TESTING.md` — unit + UI test harness, mock scenarios
