# EstiSeries backend

Zero-dependency Node.js service — the only component that holds the YouCam
API key. Implements **API contract v2** (`docs/api-contract-v2.md`).

## What it does

- **Practitioners → clients → scans**, persisted in `data.json` (JSON file
  store, atomic writes; gitignored — it contains access tokens).
- Practitioner endpoints under `/api/me` require
  `Authorization: Bearer <practitionerToken>`; clients are created with
  `POST /api/practitioners`. `POST /api/login` exists for the seeded demo
  judge account.
- Client endpoints are keyed by the client token (`/api/clients/<token>`) —
  the token inside the client's personal link (`/?c=<token>`). Scans run the
  real YouCam async flow and the mapped result is appended to that client's
  series record.
- `POST /api/try` creates a one-off client under the built-in
  "EstiSeries Sample Studio" practitioner for the public "Try a real scan"
  path.
- Seeded data exists ONLY as the judge demo accounts (demo practitioner +
  demo client, from `seed-demo.json`, created at store init when absent).
  There is no demo mode and no seeded scan results anywhere else.

## Run

```sh
cp .env.example .env   # put YOUCAM_API_KEY in .env (never commit it)
node server.js         # PORT env optional, default 8787
curl localhost:8787/health   # {"ok":true,"mode":"live"}
```

Without a key the store endpoints still work and `/health` reports
`mode:"unconfigured"`; scan requests return `error_not_configured`.

## Notes

- Live task ids are held in memory; a restart loses in-flight tasks.
  Completed results are already persisted in the client's series.
- YouCam results expire provider-side after ~24h — another reason results
  are cached here in the series record.
