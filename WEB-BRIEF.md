# WEB-BRIEF — SkinSeries client web flow (static, in `web/`)

Read `SPEC.md` first — it is the contract. Build a static mobile-first web flow in
the repo's `web/` directory: `index.html`, `styles.css`, `app.js`, `demo-data.js`
(plain script tags, NO build step, NO modules — must work from any static server).
`demo-data.js` defines `window.DEMO_DATA` mirroring `assets/demo/demo_data.json`
(same practice, client, scans, plan, products — copy the values exactly).

## The flow (one page, step sections shown/hidden by app.js)

Branding from DEMO_DATA.practice: Luna Glow Skin Studio header, terracotta accent,
cream background — visually consistent with the practitioner app (palette in
APP-BRIEF.md). Address the client by name: "Skin check-in for Maya R."

0. **Welcome** — practice name + tagline, what this is ("A 2-minute skin check-in
   before your visit — your results go to Ava and stay on your phone here too."),
   Start button.
1. **Consent** — plain-language consent with ONE checkbox list (all required to
   continue; Continue disabled until checked):
   - "My photo will be used for a cosmetic skin analysis."
   - "My photo is processed by a third-party skin analysis service; their copy is
     deleted within 24 hours."
   - "My results will be shared with Luna Glow Skin Studio."
   - "I understand this is a cosmetic skin analysis — not a medical diagnosis."
   - "I can ask Luna Glow Skin Studio to delete my data at any time."
2. **Guided capture** — a camera panel: try `getUserMedia` preview if available;
   ALWAYS offer "Use a demo photo instead" (that's the path that must work in
   demos/emulators — use a CSS face-placeholder graphic, no external images).
   Photo quality tips list (bright, even light · face fills the frame · glasses
   off · hair off forehead). "Analyze my photo" button → DEMO BEHAVIOR: first
   attempt returns the simulated error `error_lighting_dark` → show a coaching
   card: "It's a bit dark — face a window or turn on a brighter light, then try
   again." Second attempt succeeds → brief "Analyzing…" state → advance.
   Implement this as a small mock of the real API contract (comment it): in live
   mode this POSTs to the backend `/api/scans` and polls; error codes map to
   coaching messages: error_lighting_dark → lighting tip; error_src_face_too_small
   → "Move a little closer so your face fills the frame."
3. **Your report** — from the LATEST scan (session 6): overall score big, skin age,
   skin type; top-3 focus areas with band labels + one plain sentence each
   (generated from score bands, e.g. "Moisture is at 63 — much better than your
   baseline of 42, and still worth daily support."); a compact all-concerns list
   with scores. Disclaimer line (SPEC) at the foot.
4. **Your series timeline** — the centerpiece: vertical timeline of the 3 scans
   (Baseline Jul 13 → Session 3 Aug 24 → Session 6 Oct 5) with overall score at
   each stop; per-concern delta table vs baseline for at least the plan's focus
   concerns (moisture +21, redness +16, radiance +18) plus any concern that fell
   (age spots −2) shown honestly; "Your plan from Ava" card (series name, session
   count, focus notes, AM/PM regimen, products with prices) from DEMO_DATA plan;
   next-session prompt card: "Series complete — Ava recommends a maintenance
   facial next." + "Book your next visit" button linking to practice.bookingUrl.
   Disclaimer at the foot.

## Rules

- Cosmetic language only (see SPEC claims discipline). No external assets/CDNs —
  everything local so it runs offline from a static folder.
- Accessible basics: real buttons, labels on inputs, readable contrast, works at
  360px width.
- Do not touch the Flutter app or `backend/`. Do not commit — leave for review.
