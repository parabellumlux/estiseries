# APP-BRIEF — SkinSeries practitioner app (Flutter)

Read `SPEC.md` first — it is the contract. Build in the repo root (Flutter project,
package `com.ignisalgos.skinseries`). Seeded data lives at
`assets/demo/demo_data.json` (declare it in pubspec assets).

## Architecture (keep it simple, no state-management packages)

- `lib/models.dart` — Practice, Product, SeriesTemplate, SkinScan, ClientPlan,
  ClientProfile; `fromJson` factories matching the seeded JSON exactly.
- `lib/services/skin_analysis_service.dart` — abstract `SkinAnalysisService` with
  `Future<ScanResult> analyze({required String stage})` plus a `ScanException`
  carrying a YouCam-style `errorCode`.
  - `DemoSkinAnalysisService` — returns the seeded scan for the requested stage
    (baseline/session3/session6) after a short delay.
  - `LiveSkinAnalysisService` — POSTs to a configurable backend base URL
    (`AppConfig.backendBaseUrl`, default `http://10.0.2.2:8787`) endpoint
    `/api/scans` and maps the JSON response into `ScanResult`. Real code, but it is
    NOT exercised in this build (no API key exists yet) — mark it clearly in a
    comment. Do not fake-test it.
- `lib/services/demo_repository.dart` — loads + parses the asset JSON once.
- `lib/state/app_state.dart` — one `ChangeNotifier` holding practice fields, the
  demo client, and the editable plan draft; Setup and Plan screens read/write it so
  edits flow between screens.
- `lib/util/score_bands.dart` — band label for a score (per SPEC) + helpers:
  topFocusConcerns(scan) (3 lowest), biggestGains(baseline, latest).

## Screens (exactly three, bottom NavigationBar: Setup / Brief / Plan)

Warm spa palette: cream background #FAF6F1, terracotta primary #B0714F, sage
accent #7D8C74, dark warm text #2E2620. Material 3. No medical iconography.

1. **SetupScreen** — "Your practice" form pre-filled from seeded data (name,
   practitioner, booking URL) editable via AppState; accent color: 3 swatches
   (terracotta/sage/plum) that recolor the app primary. "Client scan link" card:
   the scan URL as selectable text, a QR of it (add `qr_flutter` dependency), and a
   short explanation: "Text or email this link — clients scan from home before
   their visit. No app to install." A "Demo mode" badge (Chip) in the AppBar of
   every screen.
2. **BriefScreen** ("Pre-visit brief") — client header (Maya R., series name,
   "Session 6 of 6 · last scan Oct 5, 2026"), two stat cards (Overall 74, Skin age
   44), "Focus areas" = 3 lowest scores of latest scan with band labels,
   "Biggest gains since baseline" = top 3 positive deltas with +N chips, and
   "Talking points" — 3 plain sentences GENERATED from the data (e.g. lead with the
   biggest gain; name the honest flat area: age spots −2; connect focus areas to
   the plan). Footer disclaimer from SPEC verbatim.
3. **PlanScreen** ("Plan builder") — series template dropdown (from seeded
   templates; selecting one sets session count + default focus), session count
   stepper (1–12), focus-concern chips (multi-select of the 15 concerns) each with
   an optional note field, AM/PM regimen text fields, product multi-select with
   prices and a running total, and a primary button "Share plan to client view" →
   updates AppState, shows a SnackBar "Plan shared — Maya will see it in her
   series timeline" and an expandable "Client preview" card summarizing exactly
   what the client sees (series, sessions, focuses + notes, regimen, products).

## Rules

- Cosmetic language only (see SPEC). Never the words diagnosis/diagnose/medical.
- `flutter analyze` must pass with no issues. Add 2–3 unit tests under `test/` for
  score bands + delta helpers and make `flutter test` pass.
- Do not touch `web/` or `backend/`. Do not commit — leave the tree for review.
- AndroidManifest label must read "SkinSeries".
