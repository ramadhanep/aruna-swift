# API Contract

Backend is unchanged from the Flutter app. Base URL: `AppConfig.apiBaseURL`
(prod `https://aruna.rdyy.me/api`, fallback `https://arunaa.vercel.app/api`).
Market endpoints never receive an Authorization header.

## Secure payload wrapping

Responses may wrap the body in `{"payload": "<base64>"}`. When the root JSON
contains a `payload` string, `APIClient.decode` transparently replaces the
decoded body with `SecurePayload.decode(payload, key:)`:

1. strict base64-decode (invalid alphabet → fail)
2. UTF-8 encode the key
3. XOR each cipher byte with `key[i % key.count]`
4. UTF-8 decode → JSON decode (top-level scalars allowed)

Any invalid input returns `nil` → `APIError.payloadDecodeFailed`. This must stay
byte-compatible with the Flutter algorithm.

## Endpoints

| Method | Path | Params | Returns |
|---|---|---|---|
| POST | `/quotes` | body `{"symbols": [...], "timeframe": "1D"}` | `{"quotes": {SYMBOL: quote}}` or list of quotes |
| GET | `/symbol-search` | `q` | `{"symbols": [...]}` or list |
| GET | `/price-series` | `symbol`, `timeframe` | `{"data": [...]}` / `{"quotes": [...]}` / list |
| GET | `/fundamentals` | `symbol` | object → `FundamentalsSummary` |
| GET | `/finance` | `symbol`, `startDate`, `endDate` (unix seconds) | `{"data": [...]}` / list; latest row with positive `adjclose`/`close`/`price` wins |

Quote model (subset): `symbol`, `name`, `price`, `changePercent`, `currency`.

## Error semantics

`APIClient.decode` throws, in order:

- `APIError.transport` — non-HTTP response (e.g. `URLError`)
- `APIError.invalidResponse` — non-empty body fails to JSON-parse
- `APIError.payloadDecodeFailed` — `payload` wrapper present but undecodable
- `APIError.http(status:message:)` — non-2xx; `message` from `error` field if
  present, else `"Request failed."`

`APIClientProtocol` (`get`/`post`) is the seam tests stub via `MockURLProtocol`
(unit) and `UITestURLProtocol` (UI).

## Supabase

- Auth: Google OAuth, PKCE, `aruna://login-callback/` redirect.
- Watchlist sync: one `watchlists` row per user (`user_id`, `items`,
  `updated_at`); whole-list JSON document upsert. Remote is best-effort — local
  storage is the source of truth.
