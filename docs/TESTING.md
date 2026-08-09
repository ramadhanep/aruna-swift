# Testing

Run everything from Xcode (`Product > Test`, ⌘U) or:

```sh
xcodebuild test -project aruna.xcodeproj -scheme aruna
```

## Unit tests (`arunaTests/`)

- `APIClientTests` — request building, decode paths, error mapping (uses
  `MockURLProtocol`).
- `SecurePayloadTests` — XOR/base64 decode, invalid-input cases.
- `MarketRepositoryTests` — endpoint parsing, symbol normalization.
- `WatchlistRepositoryTests` — load/save, dedupe/order, seeding, remote
  fallback, `WatchlistLoadOverride`.
- `WatchlistViewModelTests` — controller behavior.
- `StorageTests` / `ModelsTests` / `FormattersTests` — persistence, JSON
  models, formatting.
- `StartupTests` / `Phase2Tests` / `MockProbeTests` — boot state machine and
  harness probes.

Test doubles: `TestDoubles.swift` (fake repos/auth), `MockURLProtocol.swift`
(URLSession stub).

## UI tests (`arunaUITests/`)

Deterministic and offline. The app routes the live `APIClient` through
`UITestURLProtocol` (a `URLProtocol` stub) when launched with:

- `-uitest-api-mock` — offline canned API
- `-uitest-watchlist-empty` / `-uitest-watchlist-fail` — force watchlist
  load overrides
- `-uitest-reset` — clear persisted settings for a known start state

Scenario switching via `UITEST_API_MODE` environment var: `standard`,
`quotes-fail`, `quotes-fail-on-refresh`, `search-fail`, `search-empty`.

Test support code lives in the app target under `aruna/App/UITestSupport.swift`
so the UI-test target can trigger it through launch arguments; it is never
reachable in normal launches.
