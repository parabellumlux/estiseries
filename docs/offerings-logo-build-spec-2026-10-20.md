# EstiSeries "Offerings + Logo" build spec — 2026-10-20

DC's request (2026-10-20): in the practitioner app, the provider must be able to configure the services and products her spa actually offers (e.g. Botox, RF microneedling) with prices, and upload her logo.

## Environment / access
- Repo: luci `~/skinseries` (git master; GitHub mirror parabellumlux/estiseries).
- sky (production) is reached ONLY via luci jump host: from luci, `ssh damon@129.121.79.156`. Site: https://estiseries.ignisalgos.com, app home /home/damon/estiseries-app, systemd service `estiseries`, backend port 3119, nginx proxies /api/ and /health, web root /home/damon/estiseries-app/web/.
- Use OpenCode (`opencode run`) on luci for code edits per DC's standing preference; verify its output. If OpenCode hits a rate limit, switch models and retry.
- Read `docs/api-contract-v2.md` first — it defines the existing contract being extended. Backend is zero-dependency Node (backend/server.js) with a JSON file store (data.json, atomic writes, DATA_PATH env). `publicPractitioner(p)` shapes profile responses. Routes for the signed-in practitioner live under /api/me with Bearer token auth.

## BACKEND (backend/server.js)
1. Practitioner record gains `offerings` (array, default [] when absent — migrate on load without touching other fields) and `logo` (null when absent).
2. Offering shape: `{id, kind: "service"|"product", name, price, unit?, durationMin?, description?, active, createdAt}`. Server mints id on create.
3. Endpoints (Bearer, own scope only):
   - GET /api/me/offerings → full array (including inactive)
   - POST /api/me/offerings {kind, name, price, unit?, durationMin?, description?, active?} → 201 offering. Validate: kind in {service, product}; name non-empty ≤120 chars; price a finite number 0–100000; durationMin, if present, int 0–1440. Invalid → 400 {status:"error", errorCode:"error_invalid_offering"}.
   - PUT /api/me/offerings/:offeringId → updated offering (same validation); unknown id → 404 error_offering_not_found.
   - DELETE /api/me/offerings/:offeringId → {ok:true}; unknown id → 404 error_offering_not_found.
4. Logo:
   - PUT /api/me/logo (Bearer) {imageBase64, contentType} — accept only image/png, image/jpeg, image/webp; decoded bytes ≤ 2 MB else 413 {status:"error", errorCode:"error_logo_too_large"}; wrong type → 400 error_logo_type. Store bytes at backend/logos/<practitionerId>.<ext> (ext from content type); set practitioner.logo={ext, updatedAt}; respond with the profile (publicPractitioner shape).
   - DELETE /api/me/logo (Bearer) → delete file if present, clear field, respond profile.
   - GET /api/practitioners/:practitionerId/logo (PUBLIC, no auth — the client web page displays it) → bytes with correct Content-Type and `Cache-Control: public, max-age=300`; no logo → 404 {status:"error", errorCode:"error_logo_not_found"}.
   - publicPractitioner() gains `logoUrl`: "/api/practitioners/<id>/logo" when a logo is set, else null.
5. GET /api/clients/:token (public client view): the practitioner object gains `logoUrl` (same rule) AND `offerings` = the practitioner's ACTIVE offerings only.
6. Demo seed migration: on store load, if the seeded DEMO practitioner (demo:true, login demo@estiseries.app) has NO offerings field at all, seed exactly: services — {name:"Botox® Cosmetic", price:12, unit:"per unit"}, {name:"RF Microneedling", price:350, unit:"per session", durationMin:60}, {name:"Signature Glow Facial", price:120, durationMin:60}; products — {name:"Gentle Renewal Cleanser", price:38}, {name:"Hydration Boost Serum", price:64}. All active. No other practitioner's data changes.
7. .gitignore: add `backend/logos/`.
8. Update docs/api-contract-v2.md: add a "v2.1 additions (2026-10-20)" section documenting offerings CRUD, logo endpoints, logoUrl, client-view offerings, and the plan `service` field.
9. Test locally before deploying: run the backend on luci against a TEMP DATA_PATH copy; curl-exercise: create practitioner → logo 404 → upload tiny PNG logo → public GET returns image/png → POST/PUT/DELETE offerings incl. validation failures (bad kind, negative price) → cross-practitioner isolation (second practitioner's token cannot see/modify first's offerings; logo GET for a practitioner without logo 404s) → client view shows only active offerings + logoUrl. Use simulateError-free paths only; do NOT run real YouCam scans (no unit spend).

## FLUTTER APP (lib/, pubspec.yaml)
1. pubspec: add `image_picker` (latest stable compatible), version → 1.1.2+6. If `flutter pub get` cannot resolve/fetch image_picker (network), STOP and report that blocker — do not substitute another approach.
2. models.dart: `Offering` class (fromJson/toJson/copyWith; fields above). PractitionerProfile gains `logoUrl` (String?, fromJson + copyWith). ClientPlan gains optional service: plan JSON key `service` = {name, price, unit?} — parse tolerantly (absent → null), serialize when set.
3. services/api_client.dart: getOfferings(), createOffering(Offering), updateOffering(Offering), deleteOffering(String id), uploadLogo(Uint8List bytes, String contentType) → returns updated profile, deleteLogo() → updated profile. Follow the existing Bearer/error patterns in that file.
4. state/app_state.dart: hold `offerings` list; load after bootstrap/sign-in; CRUD methods that refresh state; uploadLogo/removeLogo updating profile. Keep existing patterns.
5. screens/setup_screen.dart — in the signed-in profile view add:
   - "Practice logo" section: current logo via Image.network(<backend base>+logoUrl, height ~72, fit contain) or a placeholder box; "Upload logo"/"Change logo" button using ImagePicker().pickImage(source: gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85), then upload bytes with the picked file's mime type (default image/jpeg); "Remove logo" when one is set. Surface failures with the screen's existing message style.
   - "Services & products" section: list of her offerings — each row: name, kind label (Service/Product), price formatted like $350 (append unit if set, e.g. "$12 per unit"; append "· 60 min" when durationMin set), dimmed when inactive. Tap a row → editor. Delete via trailing icon with a confirm dialog. "Add service" / "Add product" buttons → editor. Editor (dialog or pushed screen, match code style): kind preselected (editable), name field, price field ($, decimal), unit field (hint "per session, per unit…"), duration minutes field (services only), description field, Active switch, Save/Delete actions. Empty state: "Add the services and products your spa offers — Botox, RF microneedling, facials, retail products — with your prices. Clients see them on their series page, and your products appear in the Plan Builder."
6. screens/plan_screen.dart:
   - Product multi-select: use the practitioner's ACTIVE product offerings when she has any; otherwise fall back to the built-in kProducts with a small note under the section: "These are starter products — add your own in Setup."
   - Add a "Series treatment (optional)" dropdown: None + her ACTIVE services; the selection stores plan.service {name, price, unit} on save.
7. `flutter analyze` must be clean; `flutter test` must pass (existing tests; add Offering + plan-service JSON round-trip tests if quick).
8. Build release APK (`flutter build apk --release`), output name EstiSeries-v1.1.2-release.apk. MANDATORY: verify the built package declares android.permission.INTERNET (androguard venv at ~/workspace/.agvenv on the build VM, or aapt on luci). Record byte size + SHA-256.

## WEB (web/app.js, web/index.html, web/styles.css)
1. Client page (per-client link view): when practitioner.logoUrl is non-null, show the logo image at the top of the branded welcome header (max-height ~64px, object-fit contain), alongside the practice name; accent behavior unchanged.
2. New "Services & prices" section on the client page, rendered ONLY when practitioner.offerings is non-empty: group Services first, then Products; each row: name left, right side price "$350" + unit if set ("$12 per unit") + duration for services ("60 min"). Vanilla JS/DOM like the rest of app.js; styles in styles.css matching the existing design tokens.
3. Plan card: when plan.service is present, add a line "Series treatment: <name> — $<price> <unit?>" in the rendered plan/series section.
4. index.html: bump the cache-bust on app.js and styles.css links to `?v=20261020-offerings` (styles.css currently carries ?v=20261020-mirror from an earlier fix — preserve the mirror rule in styles.css itself; only the query strings change).

## DEPLOY TO SKY (shared-host protocol — mandatory, no shortcuts)
1. BEFORE changing anything: snapshot HTTP status of every service on sky — at minimum https://estiseries.ignisalgos.com/ , /styles.css, /app.js, /health, /app/EstiSeries-v1.1.1-release.apk, plus https://truegradefcg.com/donnasgift/ — and `ls -la` modes of /home/damon/estiseries-app and its web/ and backend dirs. Save the snapshot in the report.
2. Back up on sky BEFORE replacing: data.json and server.js → timestamped copies (e.g. server.js.bak-20261020-offerings, data.json.bak-20261020-offerings) in place. Find the backend's deployed path on sky first (systemd estiseries WorkingDirectory/ExecStart — `systemctl cat estiseries`).
3. Copy new server.js + web files (app.js, index.html, styles.css) from luci to sky; ensure web files are mode 644 (nginx must read them); ensure backend/logos/ exists on sky and is writable by the service user; restart `estiseries` service; confirm it comes up (systemctl status + /health).
4. AFTER snapshot: re-run the same status checks; report the diff (expect: all 200, same as before).
5. Public E2E against https://estiseries.ignisalgos.com using ONLY the demo practitioner (POST /api/login {login:"demo@estiseries.app", password:"GlowDemo2026"} → token):
   - GET /api/me → offerings present (seeded 5), logoUrl null.
   - PUT /api/me/logo with a tiny test PNG (base64, few hundred bytes) → 200; GET /api/practitioners/<demoId>/logo → 200 image/png; GET /api/clients/demo-maya-r → practitioner.logoUrl non-null, offerings = 5 active.
   - DELETE one seeded offering → GET /api/me/offerings = 4; re-POST it back identically → 5 again.
   - DELETE /api/me/logo → profile logoUrl null; public logo GET → 404. (Leave the demo account in its original state apart from the intended seeded offerings.)
   - GET /?c=demo-maya-r page → 200; served app.js contains the services-menu rendering code.
6. Publish the APK: copy EstiSeries-v1.1.2-release.apk to sky web/app/EstiSeries-v1.1.2-release.apk AND overwrite web/app/EstiSeries-v1.1.1-release.apk with the same build (shared links self-heal — established pattern). Verify both URLs return 200 with Content-Length == local byte size.
7. Git on luci: commit everything (backend, lib, web, docs, pubspec.yaml/lock, .gitignore, android if touched) with message "Practitioner offerings (services/products + prices) and logo upload; client page menu + branding; app v1.1.2" and push to origin (GitHub).

## Constraints
- No YouCam scans (zero unit spend); no changes to other sky sites/services; no recursive chmod/chown on shared paths; no root archive extraction into shared roots; the demo account must end in its original state (seeded offerings excepted); do not touch data of any real practitioner.
