# SkinSeries — Architecture

**Surfaces.** (1) Practitioner app — Flutter (`lib/`), three screens: Setup,
Pre-visit brief, Plan builder. (2) Client web flow — static site in `web/`
(no build, no login): consent → guided capture → report → series timeline.
(3) Backend proxy — zero-dependency Node service in `backend/`; the only holder
of the YouCam API key.

**Why a backend at all:** the YouCam Skin Analysis API is server-to-server
(Bearer key, async task flow). The key cannot ship in the app or web page, so
both clients talk to this proxy. Contract: `POST /api/scans`,
`GET /api/scans/<taskId>`, `GET /health` (see `backend/README.md`).

**Why not a Supabase Edge Function:** DC's Supabase org already runs two free-plan
projects (GrainSync, FleetMiles) — the free plan's project ceiling — and no API
key exists yet to wire. A small service in the repo keeps the demo self-contained;
when the key lands, this service goes live by setting one env var, and it can be
lifted into an Edge Function later without changing either client (same contract).

**Demo mode is the engine today.** No live key exists (DC's hackathon
registration is pending). The app and web flow run entirely on seeded data
(`assets/demo/demo_data.json`, mirrored in `web/demo-data.js`); the backend boots
in demo mode and serves the same seeds. The YouCam client sits behind
`SkinAnalysisService` (app) and the backend's live path — wiring the live key is
a configuration change, not a rewrite.

**Data flow (live, future):** client web flow captures → POST image to backend →
backend runs YouCam file→task→poll → result mapped to the shared ScanResult
shape (SPEC) → result cached in our store (YouCam deletes results after 24h) →
practitioner brief + client timeline read from the cache.

**Claims/privacy:** cosmetic "skin analysis" language only; explicit photo
consent before capture; third-party processing disclosed (24h deletion on
YouCam's side); client data deletable on request. See SPEC.md.
