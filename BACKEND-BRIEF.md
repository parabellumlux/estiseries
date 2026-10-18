# BACKEND-BRIEF — SkinSeries YouCam proxy (`backend/`)

Read `SPEC.md` first. Build a zero-dependency Node.js service (built-in `http`
only, Node ≥18) in `backend/server.js`. Reason it exists: the YouCam Skin Analysis
API is server-to-server — the API key must never ship in an app or web page. This
service is the only component that holds the key.

## Modes

- **Demo mode** (default; no `YOUCAM_API_KEY` in env): serves seeded results from
  `../assets/demo/demo_data.json` (read at startup; if unreadable, embed a minimal
  fallback). Never calls the internet.
- **Live mode** (`YOUCAM_API_KEY` set): implements the real YouCam async flow
  against `https://yce-api-01.makeupar.com`:
  `POST /s2s/v2.0/file/skin-analysis` → PUT image to the returned pre-signed URL →
  `POST /s2s/v2.0/task/skin-analysis` with the SD action list → poll
  `GET /s2s/v2.0/task/skin-analysis/<task_id>` until complete → map the response
  into the shared ScanResult shape (SPEC). This code path is written for real but
  is UNTESTED until DC's key exists — say so in comments and the README.

## Endpoints

- `GET /health` → `{ "ok": true, "mode": "demo" | "live" }`
- `POST /api/scans` — JSON body:
  - `{ "demoStage": "baseline" | "session3" | "session6" }` (demo mode) →
    `200 { "status": "complete", "result": <ScanResult> }` for that stage.
  - `{ "simulateError": "error_lighting_dark" | "error_src_face_too_small" }` →
    `422 { "status": "error", "errorCode": "<that code>" }` — mirrors the YouCam
    error surface so the client coaching loop can be developed against it.
  - `{ "imageBase64": "<jpeg/png base64>" }` (live mode) → runs the real flow,
    returns `{ "taskId": "...", "status": "running" }` immediately, and
    `GET /api/scans/<taskId>` returns `{ "status": "running" }` or
    `{ "status": "complete", "result": <ScanResult> }` or
    `{ "status": "error", "errorCode": "..." }`.
    In demo mode this body returns `400` with a plain explanation.
- CORS: allow all origins (local dev / demo hosting). JSON only. Port: `PORT` env
  or 8787.

## Files

- `backend/server.js`, `backend/package.json` (no dependencies, `npm start`),
  `backend/README.md` (how to run, demo vs live, how the key is supplied,
  endpoint reference), `backend/.env.example` (`YOUCAM_API_KEY=` blank + `PORT=`).
- Root `.gitignore` must include `.env` (create it if missing; Node template
  already ignores some — verify). NEVER put a real key anywhere in the repo.

## Rules

- `node --check backend/server.js` must pass; the service must boot in demo mode
  and answer `/health` and a demo `/api/scans` POST correctly.
- Cosmetic language only in any user-visible string. Do not touch app or `web/`.
  Do not commit — leave for review.
