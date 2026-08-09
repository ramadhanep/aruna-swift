# Configuration

All runtime config is resolved by `App/AppConfig.swift`. Values come from, in
order:

1. **Process environment** (`ProcessInfo.processInfo.environment`)
2. **Info.plist** — populated at build time from `Config/Config.xcconfig` via
   `$(VARIABLE)` references
3. **Code defaults** (safe placeholders)

## Secrets policy

- `Config/Config.xcconfig` is **gitignored** and holds real values locally.
- `Config/Config.xcconfig.example` is the committed template — placeholders only.
- Never hardcode real keys in source, and never commit the real xcconfig.
- To inject without an xcconfig (CI/simulator), set the matching environment
  variable instead — it takes precedence.

## Keys

| AppConfig property | Environment var | xcconfig var | Info.plist key | Default |
|---|---|---|---|---|
| `apiBaseURL` | `ARUNA_API_BASE_URL` | `API_BASE_URL` | `ARUNA_API_BASE_URL` | `https://arunaa.vercel.app/api` |
| `supabaseURL` | `SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_URL` | `SUPABASE_URL` | `SUPABASE_URL` | `https://<your-project>.supabase.co` |
| `supabaseAnonKey` | `SUPABASE_ANON_KEY` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `SUPABASE_ANON_KEY` | `SUPABASE_ANON_KEY` | `<your-anon-key>` |
| `securePayloadKey` | `ARUNA_SECURE_PAYLOAD_KEY` / `SECURE_PAYLOAD_KEY` | `SECURE_PAYLOAD_KEY` | `SECURE_PAYLOAD_KEY` | `change-me-to-something-random` |
| `oauthRedirectURL` | `ARUNA_OAUTH_REDIRECT_URL` | `OAUTH_REDIRECT_URL` | `ARUNA_OAUTH_REDIRECT_URL` | `aruna://login-callback/` |

Note: `SUPABASE_URL`/`SUPABASE_ANON_KEY` accept the `NEXT_PUBLIC_*` aliases for
parity with the Flutter/Next.js setup.

## xcconfig syntax gotcha

`//` in URL schemes would start a comment, so URLs in the xcconfig use the
empty-macro trick:

```xcconfig
API_BASE_URL = https:/$()/aruna.rdyy.me/api
OAUTH_REDIRECT_URL = aruna:/$()/login-callback/
```

## Enabling Supabase

`AppConfig.isSupabaseConfigured` is true only when a real URL + non-placeholder
anon key are present. With it false, `SupabaseAuthService.makeClient()` returns
`nil` → `isConfigured == false` → app boots straight to local/guest mode, no
network, no login. This is intentional and is the Flutter parity behavior.

## Deep link

`aruna` URL scheme is registered in `Supporting/Info.plist`
(`CFBundleURLSchemes`). PKCE callback `aruna://login-callback/...` is forwarded
via `AppEnvironment.handleOpenURL` → `SupabaseAuthService.handleOpenURL` →
`client.handle(url)`.

## UI-test config

Launch-arg driven, in `App/UITestSupport.swift`:

- `-uitest-reset` — wipe persisted settings on boot
- `-uitest-api-mock` — route API through `UITestURLProtocol` (offline)
- `-uitest-watchlist-empty` / `-uitest-watchlist-fail` — force watchlist load
  overrides
- `UITEST_API_MODE` env — scenario switching (`quotes-fail`,
  `quotes-fail-on-refresh`, `search-fail`, `search-empty`, `standard`)
