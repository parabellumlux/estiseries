# EstiSeries API Contract v2 — production (2026-10-19)

Replaces the demo contract. The seeded demo dataset is retired: nothing in this
contract serves seeded results. All scan results come from the live YouCam flow
(file → PUT → task → poll → mapper in `backend/server.js`, verified 2026-10-19).

Base URL: same origin as the web flow. App default:
`https://estiseries.ignisalgos.com` (override via `SKINSERIES_BACKEND_URL`).

All bodies are JSON. Errors: `{status:"error", errorCode, message?}`.

## Auth model

- Practitioner endpoints require header `Authorization: Bearer <practitionerToken>`.
  The token is minted once by `POST /api/practitioners` and stored on the
  practitioner's device. Unknown/missing token → 401 `error_unauthorized`.
- Client endpoints are keyed by the client token in the path. The token IS the
  credential — it travels in the client's personal link (`/?c=<token>`).
  Unknown token → 404 `error_client_not_found`.
- Every read/write is scoped: a practitioner token only ever sees its own
  clients; a client token only ever sees its own series and its own tasks.

## Shapes

ScanResult: `{overall:int, skinAge:int, skinType:string, scores:{…}}` — scores
holds the 15 camelCase concern keys (wrinkle, pore, texture, acne, oiliness,
radiance, eyeBag, ageSpot, darkCircle, droopyUpperEyelid, droopyLowerEyelid,
firmness, moisture, redness, tearTrough), each an int 0–100.

Scan record: `{taskId, label, timestamp, result}` — label is `"Baseline"` for a
client's first scan, `"Scan N"` (N = position) afterwards; timestamp is ISO.

Plan: opaque JSON object owned by the app. Recommended fields:
`{seriesName, sessions, focus:[{concern,note}], regimen:{am,pm},
products:[{name,price}]}`. The backend stores/returns it untouched; the web
flow renders those fields when present.

Accent: hex string (e.g. `"#B0714F"`).

Client link: `"/?c=" + token` (path of the web flow on the same origin).

## Endpoints

### Health
`GET /health` → `{ok:true, mode:"live"}` (`mode:"unconfigured"` when no
YouCam key is set; scan POSTs then fail 503 `error_not_configured`).

### Practitioner
- `POST /api/practitioners` `{practiceName, practitionerName, accent?, bookingLink?}`
  → 201 `{id, token, practiceName, practitionerName, accent, bookingLink, createdAt}`
- `GET /api/me` (Bearer) → `{id, practiceName, practitionerName, accent, bookingLink, createdAt, clientCount}`
- `PUT /api/me` (Bearer) `{practiceName?, practitionerName?, accent?, bookingLink?}` → profile (same shape as GET /api/me)
- `GET /api/me/clients` (Bearer) → `[{id, firstName, createdAt, token, link, scanCount, latestOverall, latestScanAt, plan}]`
- `POST /api/me/clients` (Bearer) `{firstName, plan?}` → 201 full client:
  `{id, firstName, createdAt, token, link, plan, scans: []}`
- `GET /api/me/clients/:clientId` (Bearer) → `{id, firstName, createdAt, token, link, plan, scans:[scan records]}`
  — 404 `error_client_not_found` when the client is not the caller's.
- `PUT /api/me/clients/:clientId/plan` (Bearer) `{plan}` → client summary
- `DELETE /api/me/clients/:clientId` (Bearer) → `{ok:true}`

### Client (public, token-keyed)
- `GET /api/clients/:token` →
  `{practitioner:{practiceName, practitionerName, accent, bookingLink},
    client:{firstName}, plan, scans:[{label, timestamp, result}]}`
- `POST /api/clients/:token/scans` `{imageBase64, contentType?}`
  → `{taskId, status:"running"}`
  — or `{simulateError:"error_lighting_dark"|"error_src_face_too_small"}`
  → 422 `{status:"error", errorCode}` (coaching rehearsal hook: no provider
  call, no units, nothing stored — the web flow's guided first attempt).
- `GET /api/clients/:token/scans/:taskId` →
  `{status:"running"}` | `{status:"complete", result}` | `{status:"error", errorCode}`
  — 404 `error_task_not_found` for unknown ids AND for tasks owned by another client.
  On completion the result is appended to that client's `scans` exactly once.

### Try-it (public landing)
- `POST /api/try` `{firstName?}` → 201 `{token, link}` — creates a one-off
  client under the built-in sample practitioner (practice name
  "EstiSeries Sample Studio"). The visitor then uses the normal client
  endpoints with that token. No seeded data is involved anywhere.

## Retired

`POST /api/scans` with `{demoStage}` and the seeded demo store are gone.
`assets/demo/demo_data.json` and `web/demo-data.js` are removed from the tree
(git history preserves them).
