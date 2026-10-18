# SkinSeries — Product Spec (hackathon MVP)

Working name "SkinSeries" (UNVERIFIED — name check in flight; do not rename packages).
Package: `com.ignisalgos.skinseries` · Label: SkinSeries · Flutter 3.22.2 / Dart 3.4.3.

**One-liner:** The client self-scans at home before the visit; the practitioner walks in
with a plan; every scan lands on a series timeline the client owns.

## The three surfaces

1. **Practitioner app (Flutter, this repo root)** — three screens ONLY:
   - **Setup:** practice name, practitioner name, booking link, accent color;
     shows the client scan link + QR.
   - **Pre-visit brief:** selected client's latest scan translated into a consult
     brief — overall score, skin age, top focus concerns, biggest gains vs baseline,
     suggested talking points (cosmetic language only).
   - **Plan builder:** pick a series template + session count, attach per-concern
     focus notes + home regimen (AM/PM), attach retail products, share to client view.
2. **Client web flow (`web/`, static, no build step, no login, no install):**
   consent → guided capture (API error codes as coaching) → instant plain-language
   report → series timeline with per-concern deltas vs baseline + next-session prompt.
3. **Backend proxy (`backend/`, Node, zero-dependency):** holds the YouCam API key
   server-side (the YouCam Skin Analysis API is server-to-server only). Demo mode
   when no key is configured; live mode implements the real async flow.

## Demo mode (the default and the demo's engine)

There is NO live API key yet. Everything must run end-to-end on the seeded data in
`assets/demo/demo_data.json` (web mirrors it in `web/demo-data.js`):
one practice (Luna Glow Skin Studio), one demo client (Maya R.), a completed
6-session series with 3 scans (baseline → session 3 → session 6) showing strong
gains in moisture/acne/redness/radiance and honest flat/slightly-down movement in
age spot / tear trough / eyelids. A visible "Demo mode" badge appears in the app;
the web flow's capture step uses a demo photo and simulates one
`error_lighting_dark` coaching retry before succeeding.

## Data contract (shared by app, web, backend)

Scan result shape:
```json
{ "overall": 61, "skinAge": 47, "skinType": "Combination",
  "scores": { "wrinkle": 63, "pore": 60, "texture": 57, "acne": 55,
    "oiliness": 66, "radiance": 52, "eyeBag": 59, "ageSpot": 71,
    "darkCircle": 54, "droopyUpperEyelid": 78, "droopyLowerEyelid": 80,
    "firmness": 64, "moisture": 42, "redness": 58, "tearTrough": 69 } }
```
15 scored concerns (higher = healthier, 1–100) + skin type. Concern keys and labels:
wrinkle=Wrinkles, pore=Pores, texture=Texture, acne=Acne, oiliness=Oiliness,
radiance=Radiance, eyeBag=Eye bags, ageSpot=Age spots, darkCircle=Dark circles,
droopyUpperEyelid=Droopy upper eyelids, droopyLowerEyelid=Droopy lower eyelids,
firmness=Firmness, moisture=Moisture, redness=Redness, tearTrough=Tear trough.

Score bands for plain language: ≥80 "Strong" · 65–79 "Good" ·
50–64 "Fair — worth focus" · <50 "A top focus area".

## Claims & privacy discipline (non-negotiable, everywhere)

- Say "skin analysis" / "skin check-in". NEVER diagnosis, diagnose, treatment of a
  condition, medical, cure, or outcome promises.
- Consent screen precedes any capture in the client flow: photo is processed for
  cosmetic skin analysis by a third-party analysis service (images deleted from
  their servers within 24 hours); results are shared with the practice; the client
  may ask the practice to delete their data at any time.
- Disclaimer line on brief, report, and timeline: "Cosmetic skin analysis for
  consultation and progress tracking. This is not a medical diagnosis."
- No real secrets in the repo. API key only via backend env (`YOUCAM_API_KEY`),
  `.env.example` committed, real `.env` gitignored.

## Out of scope

Payments, booking engine (link field only), EMR, chat, multi-staff roles, client
native app, HD scans, VTO, Play Console / store anything.
