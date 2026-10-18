# SkinSeries backend — YouCam proxy (`backend/`)

A zero-dependency Node.js service (built-in `http` + global `fetch`, Node ≥ 18).
It is the only component in the repo that holds the YouCam Skin Analysis API key.
The YouCam (Perfect Corp YCE) Skin Analysis API is server-to-server, so the key
must never ship in the practitioner app or the client web page — both talk to
this proxy instead.

All strings returned to clients use cosmetic skin-analysis language only. This
service is not a medical device and provides no diagnosis.

## Run

```bash
cd backend
npm start          # = node server.js
```

No install step — there are no dependencies. It boots in **demo mode** by
default and never touches the network.

Check it is up:

```bash
curl http://localhost:8787/health
# {"ok":true,"mode":"demo"}
```

## Demo vs live mode

| | Demo (default) | Live |
|---|---|---|
| Enabled when | `YOUCAM_API_KEY` is unset/blank | `YOUCAM_API_KEY` is set |
| Data source | Seeded scans from `../assets/demo/demo_data.json` (read once at startup; embedded fallback if unreadable) | Real YouCam async analysis |
| Network | Never calls the internet | Calls `https://yce-api-01.makeupar.com` |

The mode is reported by `GET /health` (`"mode": "demo" | "live"`).

### How the API key is supplied

The key is read from the environment variable `YOUCAM_API_KEY`. Two ways to set it:

1. Export it: `YOUCAM_API_KEY=... npm start`
2. A local `backend/.env` file — copy `backend/.env.example` to `backend/.env`
   and fill it in. The server loads it at startup (without overriding real
   environment variables). `.env` is gitignored; **never commit a real key.**

`PORT` (default `8787`) is read the same way.

> **The live path is UNTESTED.** It is written to the published YouCam S2S docs
> (file upload → pre-signed PUT → task create → poll → map to the shared
> ScanResult shape) and is real code, but it has not been exercised end-to-end
> because no API key exists yet. Response-field mapping is deliberately
> defensive. Verify it as soon as the key lands.

## Endpoint reference

All responses are JSON. CORS allows all origins (local dev / demo hosting).

### `GET /health`

```json
{ "ok": true, "mode": "demo" }
```

### `POST /api/scans`

Request body (one of the following):

- `{ "demoStage": "baseline" | "session3" | "session6" }` — demo mode only.
  Returns the seeded scan for that stage:

  ```json
  { "status": "complete", "result": { "overall": 61, "skinAge": 47, "skinType": "Combination", "scores": { "wrinkle": 63, "...": "..." } } }
  ```

  In live mode this returns `400` (seeded stages are a demo-mode feature).

- `{ "simulateError": "error_lighting_dark" | "error_src_face_too_small" }` —
  works in both modes. Returns `422`, mirroring the YouCam error surface so the
  client's coaching loop can be developed against it:

  ```json
  { "status": "error", "errorCode": "error_lighting_dark" }
  ```

- `{ "imageBase64": "<jpeg/png base64>", "contentType": "image/jpeg" }` — live
  mode only. Starts the real analysis and returns immediately:

  ```json
  { "taskId": "…", "status": "running" }
  ```

  In demo mode this returns `400` with a plain explanation (use `demoStage`).

  Note: the base64 body limit is 25 MB. Keep client photos modest in size.

### `GET /api/scans/<taskId>`

Live mode only (task ids are in-memory; a server restart clears them). Poll
until it leaves `running`:

- `{ "status": "running" }`
- `{ "status": "complete", "result": { …ScanResult… } }`
- `{ "status": "error", "errorCode": "…" }`

In demo mode an unknown id returns `404`.

### Error shape

Errors use `{ "status": "error", "errorCode": "…", "message": "…" }` where
`errorCode` is a YouCam-style code (`error_lighting_dark`,
`error_src_face_too_small`) or a transport code (`error_bad_request`,
`error_task_not_found`, `error_upload_failed`, `error_task_start_failed`,
`error_analysis_failed`, `error_analysis_timeout`, …).

## The shared ScanResult shape

Every `result` follows the data contract in `SPEC.md`: overall score, skin age,
skin type, and 15 scored concerns (higher = healthier, 1–100).

## Files

- `server.js` — the service (zero dependencies).
- `package.json` — `npm start`, no dependencies, Node ≥ 18.
- `.env.example` — template for `backend/.env` (committed); the real `.env` is
  gitignored at the repo root.
