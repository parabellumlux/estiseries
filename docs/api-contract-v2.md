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
firmness, moisture, redness, tearTrough), each an int 0–100. A fresh live
result may also carry `masks:{concernKey: url}` — the provider's own
region-mask image per concern (signed URLs, expire ~2h after the scan).
Consumers use masks only to enhance the just-completed report (overlay on
the analyzed photo); stored history must not depend on them.

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

### Sign-in (demo judge account)
- `POST /api/login` `{login, password}` → `{token, practitioner}` (profile
  shape as GET /api/me) or 401 `error_unauthorized`. Exists so the app can
  sign in as the seeded demo practitioner; regular practitioners use their
  device-stored token.

## Seeded judge accounts (the ONLY seeded data left)

Created by the backend at store init when absent, flagged `demo: true`:

- **Demo practitioner** — Luna Glow Skin Studio, practitioner Ava Luna,
  accent `#B0714F`, the demo dataset's booking link. Sign-in:
  login `demo@estiseries.app`, password `GlowDemo2026` (returns her
  practitioner token via `POST /api/login`).
- **Demo client** — Maya R., her existing plan, and her three historical
  scans (Jul 13 / Aug 24 / Oct 5, 2026) as stored scan records. Client token
  is the fixed, shareable `demo-maya-r` → link `/?c=demo-maya-r`.

These exist so judges can be handed a login and a client link. They are
never returned by any other client's or practitioner's view, and the public
try-it path never touches them.

## Retired

`POST /api/scans` with `{demoStage}` and the seeded demo store are gone.
`assets/demo/demo_data.json` and `web/demo-data.js` are removed from the tree
(git history preserves them).

## v2.1 additions (2026-10-20) — practitioner offerings + practice logo

Practitioners configure the services and products their spa actually offers
(with prices) and a practice logo. Nothing here changes the v2 shapes above;
the additions are new fields on the practitioner record and new endpoints.

**Practitioner record** gains:
- `offerings`: array of the practitioner's own services/products (default
  `[]`; records created before v2.1 are migrated on store load).
- `logo`: `{ext, updatedAt}` or `null`. The bytes live on the server under
  `backend/logos/<practitionerId>.<ext>`, never in the JSON store.

**Offering shape**:
`{id, kind: "service"|"product", name, price, unit?, durationMin?,
description?, active, createdAt}` — `id` and `createdAt` are minted by the
server on create; `unit` is a free-text price unit ("per unit",
"per session", ...); `durationMin` is minutes (services).

**Profile shape** (`GET /api/me`, login, logo responses):
`publicPractitioner` gains `logoUrl` — `"/api/practitioners/<id>/logo"` when
a logo is set, else `null` — and `offerings` (the full array).

### Offerings endpoints (Bearer, own scope only)
- `GET /api/me/offerings` → the full array, including inactive offerings.
- `POST /api/me/offerings` `{kind, name, price, unit?, durationMin?,
  description?, active?}` → 201 the created offering. Validation: `kind` in
  {service, product}; `name` non-empty, ≤ 120 chars; `price` a finite number
  0–100000; `durationMin`, when present, an integer 0–1440. Anything else →
  400 `error_invalid_offering`.
- `PUT /api/me/offerings/:offeringId` → 200 the updated offering (same
  validation; omitted optional fields are dropped; `active` is kept when
  omitted). Unknown id → 404 `error_offering_not_found`.
- `DELETE /api/me/offerings/:offeringId` → `{ok:true}`; unknown id → 404
  `error_offering_not_found`.
- Another practitioner's token can never see or modify these: the routes
  only ever touch the caller's own record (foreign ids 404).

### Logo endpoints
- `PUT /api/me/logo` (Bearer) `{imageBase64, contentType}` — `contentType`
  must be `image/png`, `image/jpeg`, or `image/webp` (else 400
  `error_logo_type`); decoded bytes must be ≤ 2 MB (else 413
  `error_logo_too_large`). Stores the file, replaces any previous logo,
  and returns the profile.
- `DELETE /api/me/logo` (Bearer) → removes the file and field; returns the
  profile.
- `GET /api/practitioners/:practitionerId/logo` (PUBLIC, no auth — the
  client web page displays it) → the image bytes with their content type
  and `Cache-Control: public, max-age=300`. No logo → 404
  `error_logo_not_found`.

### Client view
`GET /api/clients/:token`: the `practitioner` object gains `logoUrl` (same
rule as the profile) and `offerings` — the practitioner's ACTIVE offerings
only, in stored order. The web flow renders them as a "Services & prices"
menu on the client's page and shows the logo in the branded header.

### Plan `service` field
A plan may carry `service: {name, price, unit?}` — the series' headline
treatment, chosen in the Plan Builder from the practitioner's active
services. It is a snapshot (name/price/unit copied at save time), stored
and returned with the plan like every other plan field; the web flow
renders it on the plan card as "Series treatment: <name> — <price> <unit>".

### Demo seed
On store load, a demo practitioner with no `offerings` field at all is
seeded with five active offerings (Botox® Cosmetic $12 per unit, RF
Microneedling $350 per session 60 min, Signature Glow Facial $120 60 min,
Gentle Renewal Cleanser $38, Hydration Boost Serum $64) so the judge
accounts show a populated menu. No other practitioner is seeded.
