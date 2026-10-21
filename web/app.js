// EstiSeries client web flow — plain script, no build step, no modules.
// Production flow (API contract v2, docs/api-contract-v2.md):
//   - The client token in ?c=<token> IS the credential for the personal link.
//   - GET    /api/clients/<token>              -> {practitioner, client, plan, scans}
//   - POST   /api/clients/<token>/scans        -> {taskId, status:"running"}
//             {simulateError:"error_lighting_dark"} -> 422 {status:"error", errorCode}
//             {imageBase64, contentType}       -> a live scan only; nothing pre-made
//   - GET    /api/clients/<token>/scans/<taskId>
//                                              -> {status:"running"} |
//                                                 {status:"complete", result} |
//                                                 {status:"error", errorCode}
//   - POST   /api/try {firstName}              -> 201 {token, link} (one-off client
//             under "EstiSeries Sample Studio"), then navigate to ?c=<token>.
// ScanResult: {overall, skinAge, skinType, scores:{15 camelCase concerns},
//   masks:{concernKey: provider region-mask PNG url}} — mask urls are signed
//   and expire ~2h after the scan; the report handles their failure gracefully.
// Scan record: {taskId, label, timestamp, result}.
// There is no sample data and no offline fallback anywhere in this flow.
(function () {
  "use strict";

  // ---- Concern schema (labels only — the 15 keys of a ScanResult) ----
  var CONCERNS = [
    { key: "wrinkle", label: "Wrinkles" },
    { key: "pore", label: "Pores" },
    { key: "texture", label: "Texture" },
    { key: "acne", label: "Acne" },
    { key: "oiliness", label: "Oiliness" },
    { key: "radiance", label: "Radiance" },
    { key: "eyeBag", label: "Eye bags" },
    { key: "ageSpot", label: "Age spots" },
    { key: "darkCircle", label: "Dark circles" },
    { key: "droopyUpperEyelid", label: "Droopy upper eyelids" },
    { key: "droopyLowerEyelid", label: "Droopy lower eyelids" },
    { key: "firmness", label: "Firmness" },
    { key: "moisture", label: "Moisture" },
    { key: "redness", label: "Redness" },
    { key: "tearTrough", label: "Tear trough" }
  ];
  var concernLabels = {};
  CONCERNS.forEach(function (c) { concernLabels[c.key] = c.label; });

  // ---- Backend base ----
  // The backend lives on the same host as this page, port 8787 (this page
  // is served statically on another port). window.BACKEND_BASE_URL can
  // override the base before this script loads — the hosted deployment's
  // shim sets it to the same-origin "/" so every call below is relative.
  // Trailing slashes are stripped so a same-origin override of "/" yields
  // "/health" and "/api/clients/...", not "//health".
  var BACKEND_BASE = (window.BACKEND_BASE_URL ||
    (location.protocol + "//" + location.hostname + ":8787")).replace(/\/+$/, "");

  function apiUrl(path) { return BACKEND_BASE + path; }
  function el(id) { return document.getElementById(id); }

  // ---- Score bands (per spec): higher is healthier, 0-100 ----
  function bandFor(score) {
    if (score >= 80) return "Strong";
    if (score >= 65) return "Good";
    if (score >= 50) return "Fair — worth focus";
    return "A top focus area";
  }

  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  function datePart(iso) {
    if (!iso) return "";
    return String(iso).split("T")[0];
  }
  function formatDate(iso) {
    var parts = datePart(iso).split("-");
    if (parts.length === 3) {
      var month = MONTHS[parseInt(parts[1], 10) - 1];
      if (month) return month + " " + parseInt(parts[2], 10) + ", " + parts[0];
    }
    var d = new Date(iso);
    if (!isNaN(d.getTime())) {
      return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear();
    }
    return String(iso || "");
  }
  function formatDateShort(iso) {
    var parts = datePart(iso).split("-");
    if (parts.length === 3) {
      var month = MONTHS[parseInt(parts[1], 10) - 1];
      if (month) return month + " " + parseInt(parts[2], 10);
    }
    var d = new Date(iso);
    if (!isNaN(d.getTime())) return MONTHS[d.getMonth()] + " " + d.getDate();
    return "";
  }
  function todayIso() { return new Date().toISOString(); }
  function formatPrice(price) {
    if (typeof price === "number") return "$" + price;
    if (price === null || price === undefined || price === "") return "";
    var text = String(price);
    return text.charAt(0) === "$" ? text : "$" + text;
  }
  function priceValue(price) {
    if (typeof price === "number") return price;
    var n = parseFloat(String(price).replace(/[^0-9.]/g, ""));
    return isNaN(n) ? 0 : n;
  }

  // ---- Flow state (all of it comes from the client record) ----
  var clientToken = null;
  try {
    clientToken = new URLSearchParams(window.location.search).get("c");
  } catch (e) {
    var match = window.location.search.match(/[?&]c=([^&]*)/);
    clientToken = match ? decodeURIComponent(match[1]) : null;
  }
  if (clientToken) clientToken = clientToken.trim() || null;
  var hadLinkParam = !!clientToken;
  // v2.2: /?signin=1 asks for the sign-in view; otherwise a token stored by
  // an earlier sign-in (lost-link recovery) resumes her series.
  var signinRequested = false;
  try {
    signinRequested = new URLSearchParams(window.location.search).get("signin") === "1";
  } catch (e) {
    signinRequested = /[?&]signin=1/.test(window.location.search);
  }
  if (!clientToken && !signinRequested) {
    try {
      var storedToken = window.localStorage.getItem("estiseries.clientToken");
      if (storedToken) clientToken = storedToken;
    } catch (e) {}
  }

  var practitioner = null; // {practiceName, practitionerName, accent, bookingLink}
  var clientFirstName = "";
  var clientAccount = null; // {email, emailVerified} once she creates a login (v2.2)
  var plan = null;
  var timelineScans = []; // normalized scan records, oldest first
  var acceptedScans = []; // the official series — accepted scans only (v2.3)
  var currentScan = null;  // normalized latest accepted / just-completed scan
  var baseline = null;     // normalized first accepted scan

  // A v2 scan record {label, timestamp, result, status} normalized to the
  // flat shape the renderers use. Since v2.3 a fresh scan is "pending"
  // until the practitioner accepts it; pending scans render in the
  // timeline with a marker but never feed the trend math (rings, deltas,
  // baseline/current), which is accepted-only.
  function normalizeScan(record) {
    if (!record) return null;
    var result = record.result || {};
    return {
      taskId: record.taskId || null,
      label: record.label || "Scan",
      timestamp: record.timestamp || record.date || "",
      date: datePart(record.timestamp || record.date || ""),
      overall: result.overall,
      skinAge: result.skinAge,
      skinType: result.skinType,
      scores: result.scores || {},
      masks: result.masks || {},
      pending: record.status === "pending"
    };
  }
  function applyClientRecord(body) {
    practitioner = body.practitioner || null;
    clientFirstName = (body.client && body.client.firstName) || "";
    clientAccount = (body.client && body.client.account) || null;
    plan = body.plan || null;
    timelineScans = (body.scans || []).map(normalizeScan).filter(function (s) { return s !== null; });
    acceptedScans = timelineScans.filter(function (s) { return !s.pending; });
    baseline = acceptedScans.length ? acceptedScans[0] : null;
    currentScan = acceptedScans.length ? acceptedScans[acceptedScans.length - 1] : null;
  }

  // ---- Step navigation ----
  var steps = ["step-welcome", "step-consent", "step-capture", "step-report", "step-timeline"];
  var stepNames = ["Welcome", "Consent", "Photo", "Your report", "Series timeline"];
  var currentStep = 0;
  function showStep(index) {
    currentStep = index;
    steps.forEach(function (id, i) { el(id).hidden = i !== index; });
    el("progressWrap").hidden = !practitioner;
    el("progressLabel").textContent = "Step " + (index + 1) + " of " + steps.length + " — " + stepNames[index];
    var dots = el("progressDots").children;
    for (var d = 0; d < dots.length; d++) {
      dots[d].className = d < index ? "is-done" : d === index ? "is-active" : "";
    }
    window.scrollTo(0, 0);
  }

  // ---- Branding from the resolved practitioner record ----
  function initialsFor(name) {
    var words = String(name || "").split(/\s+/).filter(function (w) { return w; });
    if (!words.length) return "ES";
    return words.slice(0, 2).map(function (w) { return w.charAt(0).toUpperCase(); }).join("");
  }
  function practitionerFirstName() {
    if (!practitioner || !practitioner.practitionerName) return "your practitioner";
    return String(practitioner.practitionerName).split(" ")[0];
  }
  function applyBranding() {
    if (!practitioner) return;
    var practiceName = practitioner.practiceName || "EstiSeries";
    el("practiceName").textContent = practiceName;
    el("practiceMark").textContent = initialsFor(practiceName);
    var logoImg = el("practiceLogo");
    if (practitioner.logoUrl) {
      logoImg.src = practitioner.logoUrl;
      logoImg.alt = practiceName + " logo";
      logoImg.hidden = false;
      el("practiceMark").hidden = true;
    } else {
      logoImg.hidden = true;
      logoImg.removeAttribute("src");
      el("practiceMark").hidden = false;
    }
    document.title = "Skin check-in — " + practiceName;
    if (practitioner.accent) {
      document.documentElement.style.setProperty("--terra", practitioner.accent);
    }
    Array.prototype.forEach.call(document.querySelectorAll(".practice-name-inline"), function (span) {
      span.textContent = practiceName;
    });
    el("focusPractitionerName").textContent = practitionerFirstName();
    el("planPractitionerName").textContent = practitionerFirstName();
  }

  // ---- Welcome states ----
  function showPublicLanding() {
    practitioner = null;
    el("personalWelcome").hidden = true;
    el("invalidWelcome").hidden = true;
    el("publicWelcome").hidden = false;
    el("tryCard").hidden = false;
    el("practiceName").textContent = "EstiSeries";
    el("practiceMark").textContent = "ES";
    el("practiceLogo").hidden = true;
    el("practiceMark").hidden = false;
    document.title = "Skin check-in — EstiSeries";
    showStep(0);
    el("progressWrap").hidden = true;
  }
  function showInvalidLink(message) {
    practitioner = null;
    el("personalWelcome").hidden = true;
    el("publicWelcome").hidden = true;
    el("invalidWelcome").hidden = false;
    if (message) el("invalidText").textContent = message;
    el("tryCard").hidden = false;
    el("practiceName").textContent = "EstiSeries";
    el("practiceMark").textContent = "ES";
    el("practiceLogo").hidden = true;
    el("practiceMark").hidden = false;
    document.title = "Skin check-in — EstiSeries";
    showStep(0);
    el("progressWrap").hidden = true;
  }
  function showPersonalWelcome() {
    el("publicWelcome").hidden = true;
    el("invalidWelcome").hidden = true;
    el("tryCard").hidden = true;
    el("personalWelcome").hidden = false;
    applyBranding();

    var practiceName = practitioner.practiceName || "EstiSeries";
    var practitionerName = practitioner.practitionerName || "your practitioner";
    el("welcomeEyebrow").textContent = "Your check-in with " + practitionerName;
    el("welcomeHeading").textContent = clientFirstName
      ? "Welcome, " + clientFirstName + " — your skin series, in your pocket."
      : "Your skin series, in your pocket.";
    el("welcomeLede").textContent =
      "A 2-minute check-in before your visit — one photo, plain-language results, and your whole series in one place. Your results go to " +
      practitionerFirstName() + " and stay on your phone here too.";
    el("welcomeExplainer").textContent =
      "This skin check-in uses a photo to create a simple, plain-language skin analysis you can review with " +
      practitionerFirstName() + " at " + practiceName +
      ". Your scans stay together on one series timeline, so you can see how your skin changes across your visits.";

    renderHero();
    renderServices();
    renderAccountCard();
    showStep(0);
  }

  // ---- Services & prices menu (the practitioner's own offerings) ----
  function renderServices() {
    var offerings = (practitioner && practitioner.offerings) || [];
    var card = el("servicesCard");
    card.hidden = !offerings.length;
    if (!offerings.length) return;
    var groups = el("servicesGroups");
    groups.innerHTML = "";
    [
      { kind: "service", label: "Services" },
      { kind: "product", label: "Products" }
    ].forEach(function (group) {
      var items = offerings.filter(function (o) {
        return o && o.kind === group.kind;
      });
      if (!items.length) return;
      var heading = document.createElement("h3");
      heading.className = "services-group-title";
      heading.textContent = group.label;
      groups.appendChild(heading);
      var list = document.createElement("ul");
      list.className = "product-list";
      items.forEach(function (o) {
        var item = document.createElement("li");
        var nameEl = document.createElement("span");
        nameEl.textContent = o.name || "";
        var priceEl = document.createElement("span");
        var text = formatPrice(o.price);
        if (o.unit) text += " " + o.unit;
        if (group.kind === "service" && o.durationMin) {
          text += " · " + o.durationMin + " min";
        }
        priceEl.textContent = text;
        item.appendChild(nameEl);
        item.appendChild(priceEl);
        list.appendChild(item);
      });
      groups.appendChild(list);
    });
  }

  // ---- Welcome hero: the client's own series, up front ----
  function renderHero() {
    var hasScans = timelineScans.length > 0;
    el("seriesPreview").hidden = !hasScans;
    el("noScansNote").hidden = hasScans;
    if (!hasScans) return;

    el("seriesPreviewTitle").textContent = clientFirstName
      ? clientFirstName + "'s series so far"
      : "Your series so far";
    var sub = "";
    if (plan && plan.seriesName) {
      sub = plan.seriesName + (plan.sessions ? " · " + plan.sessions + " sessions" : "");
    }
    el("seriesPreviewSub").textContent = sub;

    var arc = el("heroArc");
    arc.innerHTML = "";
    timelineScans.forEach(function (scan, i) {
      if (i > 0) {
        var link = document.createElement("span");
        link.className = "arc-link";
        link.setAttribute("aria-hidden", "true");
        arc.appendChild(link);
      }
      var stop = document.createElement("div");
      stop.className = scan.pending ? "arc-stop arc-stop-pending" : "arc-stop";
      var ring = document.createElement("div");
      ring.className = "score-ring score-ring-sm";
      ring.style.setProperty("--p", scan.overall || 0);
      var value = document.createElement("span");
      value.className = "score-ring-value";
      value.textContent = scan.overall;
      ring.appendChild(value);
      var label = document.createElement("p");
      label.className = "arc-label";
      label.textContent = scan.label;
      var date = document.createElement("p");
      date.className = "arc-date";
      date.textContent = formatDateShort(scan.timestamp);
      stop.appendChild(ring);
      stop.appendChild(label);
      stop.appendChild(date);
      if (scan.pending) {
        var pendingNote = document.createElement("p");
        pendingNote.className = "arc-pending";
        pendingNote.textContent = "Pending review";
        stop.appendChild(pendingNote);
      }
      arc.appendChild(stop);
    });

    var showDeltas = acceptedScans.length >= 2 && baseline && currentScan;
    el("heroDeltasTitle").hidden = !showDeltas;
    var chips = el("heroDeltas");
    chips.innerHTML = "";
    if (!showDeltas) return;
    // Trend chips compare the accepted baseline with the latest ACCEPTED
    // scan — never a pending one (v2.3).
    var heroBase = acceptedScans[0];
    var heroNow = acceptedScans[acceptedScans.length - 1];
    function addChip(key) {
      if (!heroBase.scores || !heroNow.scores) return;
      if (typeof heroBase.scores[key] !== "number" || typeof heroNow.scores[key] !== "number") return;
      var delta = heroNow.scores[key] - heroBase.scores[key];
      if (delta === 0) return;
      // Avoid duplicate chips when a focus concern also declined.
      for (var i = 0; i < chips.children.length; i++) {
        if (chips.children[i].getAttribute("data-key") === key) return;
      }
      var chip = document.createElement("span");
      chip.className = "delta-chip " + (delta > 0 ? "delta-chip-up" : "delta-chip-down");
      chip.setAttribute("data-key", key);
      chip.textContent = (concernLabels[key] || key) + " " +
        (delta > 0 ? "+" + delta : "−" + Math.abs(delta));
      chips.appendChild(chip);
    }
    if (plan && plan.focus) {
      plan.focus.forEach(function (f) { addChip(f.concern); });
    }
    CONCERNS.forEach(function (c) {
      if (heroBase.scores && heroNow.scores &&
          typeof heroBase.scores[c.key] === "number" && typeof heroNow.scores[c.key] === "number" &&
          heroNow.scores[c.key] - heroBase.scores[c.key] < 0) addChip(c.key);
    });
  }

  el("startBtn").addEventListener("click", function () { showStep(1); });

  // ---- Try-it (public landing + invalid-link state) ----
  el("tryBtn").addEventListener("click", function () {
    var firstName = el("tryFirstName").value.trim();
    var button = el("tryBtn");
    button.disabled = true;
    el("tryStatus").textContent = "Starting your check-in…";
    fetch(apiUrl("/api/try"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ firstName: firstName })
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (body) {
        return { httpStatus: r.status, body: body };
      });
    }).then(function (res) {
      if ((res.httpStatus === 200 || res.httpStatus === 201) && res.body && res.body.token) {
        var target = res.body.link || (window.location.pathname + "?c=" + encodeURIComponent(res.body.token));
        window.location.assign(target);
        return;
      }
      button.disabled = false;
      el("tryStatus").textContent = "We could not start a check-in just now — please try again.";
    }).catch(function () {
      button.disabled = false;
      el("tryStatus").textContent = "We could not start a check-in just now — please try again.";
    });
  });

  // ---- Consent: Continue stays disabled until every box is checked ----
  var consentChecks = Array.prototype.slice.call(document.querySelectorAll(".consent-check"));
  function refreshConsent() {
    var allChecked = consentChecks.every(function (box) { return box.checked; });
    el("consentContinueBtn").disabled = !allChecked;
    el("consentHint").textContent = allChecked
      ? "Thank you — you are ready to continue."
      : "All five boxes are needed so we can run your skin analysis.";
  }
  consentChecks.forEach(function (box) { box.addEventListener("change", refreshConsent); });
  refreshConsent();
  el("consentBackBtn").addEventListener("click", function () { showStep(0); });
  el("consentContinueBtn").addEventListener("click", function () { showStep(2); });

  // ---- Guided capture ----
  // Attempt 1 rehearses the coaching loop through the backend's
  // simulateError hook (no provider call, no units, nothing stored).
  // Attempt 2 sends a real photo: camera frame (getUserMedia) or a chosen
  // photo file. Photo-quality errorCodes map to the coaching card with a
  // retry; every other error maps to a plain status message.
  var COACHING = {
    error_lighting_dark: "It's a bit dark — face a window or turn on a brighter light, then try again.",
    error_src_face_too_small: "Move a little closer so your face fills the frame."
  };
  var ERROR_MESSAGES = {
    error_upload_failed: "That photo could not be processed — try a clearer, front-facing photo in bright light.",
    error_analysis_failed: "The analysis did not finish — please try again with a clear, front-facing photo.",
    error_network: "We could not reach the analysis service — check the connection and try again.",
    error_timeout: "The analysis is taking longer than usual — please try again.",
    error_task_not_found: "That scan could not be found — please try again.",
    error_client_not_found: "This link isn't active — ask your practitioner for your personal link.",
    error_not_configured: "The analysis service is not available right now — please try again later."
  };
  function isPhotoQualityError(code) {
    return !!code && (!!COACHING[code] || code.indexOf("error_src_") === 0);
  }
  function messageForError(code) {
    if (COACHING[code]) return COACHING[code];
    if (code && code.indexOf("error_src_") === 0) {
      return "That photo could not be used — face the camera straight on, fill the frame with your face, and try again in bright, even light.";
    }
    return ERROR_MESSAGES[code] ||
      "Something went wrong with that photo (" + code + ") — please try again.";
  }

  var analyzeAttempts = 0;
  var cameraStream = null;
  var photoReady = false;
  var photoSource = null; // "camera" | "file"
  var capturedImageBase64 = null;
  var capturedContentType = "image/jpeg";
  var capturedPhotoDataUrl = null; // data: url of the in-page photo, kept for the report overlay
  var lastCompletedResult = null;   // the just-completed ScanResult (fresh masks live here)

  function setPhotoReady(ready, note) {
    photoReady = ready;
    if (note) el("cameraNote").textContent = note;
  }
  function showPreview(dataUrl) {
    var img = el("capturedPreview");
    img.src = dataUrl;
    img.hidden = false;
    el("cameraVideo").hidden = true;
    el("facePlaceholder").hidden = true;
  }
  function hidePreview() {
    el("capturedPreview").hidden = true;
    el("capturedPreview").removeAttribute("src");
  }

  // ---- Face guide (Addendum 2) ----
  // An oval over the preview: white while placement is wrong, green when the
  // face is centered, the right size, and the light is adequate. Checks are
  // lightweight and client-side only, zero dependencies:
  //   - the native FaceDetector API where available (face bounding box), with
  //   - a canvas fallback: frame luminance + skin-tone pixel centroid / box.
  // The guide is advice, never a gate: the shutter stays usable while white,
  // and a not-yet-green capture still flows into the backend coaching loop.
  var guideTimer = null;
  var guideBusy = false;
  var guideDetector = null;
  var guideCanvas = document.createElement("canvas");
  var guideGoodStreak = 0, guideBadStreak = 0, guideShownGood = false;
  try {
    if ("FaceDetector" in window) guideDetector = new window.FaceDetector({ fastMode: true, maxDetectedFaces: 1 });
  } catch (e) { guideDetector = null; }

  function setGuide(good, statusText) {
    var oval = el("faceGuideOval");
    var status = el("faceGuideStatus");
    if (!oval || !status) return;
    oval.className = "face-guide-oval " + (good ? "is-good" : "is-bad");
    status.className = "face-guide-status " + (good ? "is-good" : "is-bad");
    if (statusText) status.textContent = statusText;
  }
  function assessPlacement(m) {
    // m: {brightness, box:{cx,cy,w}|null, skin:{ratio,cx,w}|null}
    if (typeof m.brightness === "number") {
      if (m.brightness < 50) return { good: false, reason: "Too dark — face a window or brighter light" };
      if (m.brightness > 248) return { good: false, reason: "Very bright — soften the light a little" };
    }
    var box = m.box || m.skin;
    if (!box) return { good: false, reason: "No face detected — position your face in the oval" };
    if (box.w < 0.42) return { good: false, reason: "Move a little closer" };
    if (box.w > 0.86) return { good: false, reason: "Move back a little" };
    if (Math.abs(box.cx - 0.5) > 0.18 || Math.abs(box.cy - 0.47) > 0.22) {
      return { good: false, reason: "Center your face in the oval" };
    }
    return { good: true, reason: "Good — you're well placed" };
  }
  function isSkinPixel(r, g, b) {
    // Two tests, either may pass: the classic RGB rule (loosened) and a
    // YCbCr rule, which holds up far better across lighting and skin tones.
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    if (r > 55 && g > 30 && b > 15 && r > g && r > b && (r - b) > 10 && (mx - mn) > 8 && (mx - mn) < 170) return true;
    var cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    var cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    return cb > 77 && cb < 127 && cr > 133 && cr < 173;
  }
  function frameMetrics(source, srcW, srcH) {
    // Draw the source down to a small canvas and read luminance + skin pixels.
    var w = 160;
    var h = Math.max(1, Math.round(w * (srcH / srcW)));
    guideCanvas.width = w; guideCanvas.height = h;
    var ctx = guideCanvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(source, 0, 0, w, h);
    var data;
    try { data = ctx.getImageData(0, 0, w, h).data; } catch (e) { return { brightness: null, box: null, skin: null }; }
    var lumSum = 0, count = 0;
    var skinCount = 0, skinX = 0, skinY = 0;
    var colCounts = {};
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        var i = (y * w + x) * 4;
        var r = data[i], g = data[i + 1], b = data[i + 2];
        lumSum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        count++;
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
        if (isSkinPixel(r, g, b)) {
          skinCount++; skinX += x; skinY += y;
          colCounts[x] = (colCounts[x] || 0) + 1;
        }
      }
    }
    var skin = null;
    if (count && skinCount / count > 0.012) {
      // Span from the 2%..98% percentile columns, so stray skin-colored
      // background pixels cannot stretch or shrink the measured face width.
      var lo = 0.02 * skinCount, hi = 0.98 * skinCount, cum = 0, spanMin = null, spanMax = null;
      var cols = Object.keys(colCounts).map(Number).sort(function (a, b) { return a - b; });
      for (var ci = 0; ci < cols.length; ci++) {
        cum += colCounts[cols[ci]];
        if (spanMin === null && cum >= lo) spanMin = cols[ci];
        if (cum >= hi) { spanMax = cols[ci]; break; }
      }
      if (spanMax === null) spanMax = cols[cols.length - 1];
      if (spanMin === null) spanMin = cols[0];
      skin = { ratio: skinCount / count, cx: (skinX / skinCount) / w, cy: (skinY / skinCount) / h, w: (spanMax - spanMin) / w };
    }
    return { brightness: count ? lumSum / count : null, box: null, skin: skin };
  }
  function detectBox(source, srcW, srcH) {
    if (!guideDetector) return Promise.resolve(null);
    return guideDetector.detect(source).then(function (faces) {
      if (!faces || !faces.length || !faces[0].boundingBox) return null;
      var bb = faces[0].boundingBox;
      return { cx: (bb.x + bb.width / 2) / srcW, cy: (bb.y + bb.height / 2) / srcH, w: bb.width / srcW };
    }).catch(function () { return null; });
  }
  function runGuideCheck(source, srcW, srcH) {
    if (!srcW || !srcH) return;
    var metrics;
    try { metrics = frameMetrics(source, srcW, srcH); } catch (e) { return; }
    detectBox(source, srcW, srcH).then(function (box) {
      if (box) metrics.box = box;
      var verdict = assessPlacement(metrics);
      // Two-frame smoothing each way: one noisy frame can no longer flip
      // the oval, and green no longer needs a single perfect frame.
      if (verdict.good) {
        guideGoodStreak++; guideBadStreak = 0;
        if (guideGoodStreak >= 2) guideShownGood = true;
      } else {
        guideBadStreak++; guideGoodStreak = 0;
        if (guideBadStreak >= 2) guideShownGood = false;
      }
      var text = verdict.good
        ? (guideShownGood ? verdict.reason : "Almost there \u2014 hold it right there")
        : verdict.reason;
      setGuide(guideShownGood, text);
    });
  }
  function startGuideLoop() {
    stopGuideLoop();
    guideGoodStreak = 0; guideBadStreak = 0; guideShownGood = false;
    var tick = function () {
      if (!cameraStream) return;
      var video = el("cameraVideo");
      if (video && video.videoWidth && !guideBusy) {
        guideBusy = true;
        try { runGuideCheck(video, video.videoWidth, video.videoHeight); } catch (e) { /* guide is best-effort */ }
        guideBusy = false;
      }
      guideTimer = setTimeout(tick, 700);
    };
    guideTimer = setTimeout(tick, 350);
  }
  function stopGuideLoop() {
    if (guideTimer) { clearTimeout(guideTimer); guideTimer = null; }
  }
  function checkStillPhoto(img) {
    // One guide pass over a chosen/preview photo (same checks as the camera).
    var probe = new Image();
    probe.onload = function () {
      if (probe.naturalWidth) runGuideCheck(probe, probe.naturalWidth, probe.naturalHeight);
    };
    probe.src = img;
  }

  el("photoFileInput").addEventListener("change", function (event) {
    var file = event.target.files && event.target.files[0];
    if (!file) return;
    stopCamera();
    var reader = new FileReader();
    reader.onload = function () {
      var dataUrl = String(reader.result || "");
      var comma = dataUrl.indexOf(",");
      if (comma < 0) {
        setPhotoReady(false, "That file could not be read — please choose a photo.");
        return;
      }
      photoSource = "file";
      capturedImageBase64 = dataUrl.slice(comma + 1);
      capturedContentType = file.type || "image/jpeg";
      capturedPhotoDataUrl = dataUrl;
      showPreview(dataUrl);
      el("faceGuide").hidden = false;
      setGuide(false, "Checking your photo…");
      checkStillPhoto(dataUrl);
      setPhotoReady(true, "Photo chosen — this is the photo we will use for your skin analysis.");
      el("coachingCard").hidden = true;
      el("analyzeStatus").textContent = "";
    };
    reader.onerror = function () {
      setPhotoReady(false, "That file could not be read — please choose a photo.");
    };
    reader.readAsDataURL(file);
  });

  el("cameraBtn").addEventListener("click", function () {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setPhotoReady(photoReady, "Camera is not available on this device — choose a photo instead.");
      return;
    }
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false })
      .then(function (stream) {
        cameraStream = stream;
        photoSource = "camera";
        capturedImageBase64 = null;
        capturedPhotoDataUrl = null;
        capturedContentType = "image/jpeg";
        hidePreview();
        var video = el("cameraVideo");
        video.srcObject = stream;
        video.hidden = false;
        el("facePlaceholder").hidden = true;
        el("faceGuide").hidden = false;
        setGuide(false, "Position your face in the oval");
        setPhotoReady(true, "Camera on — hold still, look straight at the camera, then tap the round shutter button to take your photo.");
        startGuideLoop();
      })
      .catch(function () {
        setPhotoReady(photoReady, "We could not open the camera here — choose a photo instead.");
      });
  });

  function stopCamera() {
    stopGuideLoop();
    el("faceGuide").hidden = true;
    if (cameraStream) {
      cameraStream.getTracks().forEach(function (track) { track.stop(); });
      cameraStream = null;
    }
  }

  el("captureBackBtn").addEventListener("click", function () { stopCamera(); showStep(1); });

  // ---- Analysis run ----

  // The shutter button is a small round overlay button; its state is carried
  // by its caption + aria-label, never by long button text.
  function setShutterCaption(text) {
    el("shutterCaption").textContent = text;
    el("analyzeBtn").setAttribute("aria-label", text === "Take photo" ? "Take photo and analyze my photo" : text);
  }
  function setAnalyzing(on) {
    var button = el("analyzeBtn");
    button.disabled = on;
    setShutterCaption(on ? "Analyzing…" : "Take photo");
    el("analyzeStatus").textContent = on
      ? "Analyzing your photo — this takes just a moment…"
      : "";
  }

  function showCoaching(errorCode) {
    el("coachingText").textContent = messageForError(errorCode);
    el("coachingCard").hidden = false;
    setShutterCaption("Try again");
    if (typeof el("coachingCard").scrollIntoView === "function") {
      try { el("coachingCard").scrollIntoView({ block: "nearest" }); } catch (e) { /* nearest is best-effort */ }
    }
  }

  // A failure the client can act on: photo-quality codes get the coaching
  // card; anything else gets a plain status line. Either way she can retry.
  function failWith(errorCode) {
    setAnalyzing(false);
    if (isPhotoQualityError(errorCode)) {
      showCoaching(errorCode);
    } else {
      el("coachingCard").hidden = true;
      el("analyzeStatus").textContent = messageForError(errorCode);
      setShutterCaption("Try again");
    }
  }

  function postClientScan(body) {
    return fetch(apiUrl("/api/clients/" + encodeURIComponent(clientToken) + "/scans"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (parsed) {
        return { httpStatus: r.status, body: parsed };
      });
    });
  }

  function fetchClientRecord() {
    return fetch(apiUrl("/api/clients/" + encodeURIComponent(clientToken)))
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (body) {
          return { httpStatus: r.status, body: body };
        });
      });
  }

  function pollTask(taskId, triesLeft) {
    fetch(apiUrl("/api/clients/" + encodeURIComponent(clientToken) + "/scans/" + encodeURIComponent(taskId)))
      .then(function (r) {
        return r.json().catch(function () { return {}; });
      })
      .then(function (body) {
        if (body.status === "complete" && body.result) {
          succeedWith(body.result);
          return;
        }
        if (body.status === "error" || body.errorCode) {
          failWith(body.errorCode || "error_analysis_failed");
          return;
        }
        if (triesLeft <= 0) {
          failWith("error_timeout");
          return;
        }
        setTimeout(function () { pollTask(taskId, triesLeft - 1); }, 2000);
      })
      .catch(function () { failWith("error_network"); });
  }

  function succeedWith(result) {
    stopCamera();
    setAnalyzing(false);
    lastCompletedResult = result;
    el("coachingCard").hidden = true;
    // Render the report from the returned result right away, then re-fetch
    // the client record so the timeline is built from the stored series
    // (the completed scan is appended to it exactly once by the backend).
    // The stored record is "pending" until the practitioner accepts it
    // (v2.3) — she still sees her own report immediately.
    currentScan = normalizeScan({
      label: "Latest scan",
      timestamp: todayIso(),
      result: result,
      status: "pending"
    });
    renderReport();
    fetchClientRecord()
      .then(function (res) {
        if (res.httpStatus === 200 && res.body && res.body.practitioner) {
          applyClientRecord(res.body);
          applyBranding();
          if (!currentScan && timelineScans.length) {
            currentScan = timelineScans[timelineScans.length - 1];
          } else if (timelineScans.length) {
            currentScan = timelineScans[timelineScans.length - 1];
          }
          // The stored record may predate mask pass-through; the fresh
          // result's provider masks win for the just-completed report.
          if (currentScan && lastCompletedResult && lastCompletedResult.masks &&
              (!currentScan.masks || !Object.keys(currentScan.masks).length)) {
            currentScan.masks = lastCompletedResult.masks;
          }
          renderReport();
        }
        renderTimeline();
        showStep(3);
      })
      .catch(function () {
        // Keep the just-returned result as the newest timeline stop.
        if (currentScan) {
          currentScan.label = timelineScans.length ? "Scan " + (timelineScans.length + 1) : "Baseline";
          timelineScans = timelineScans.concat([currentScan]);
          // The appended scan is pending, so it must not become the
          // trend baseline in this fallback path.
          if (!baseline && !currentScan.pending) baseline = timelineScans[0];
        }
        renderTimeline();
        showStep(3);
      });
  }

  // Grab the current camera frame as base64 JPEG (no data: prefix), and
  // keep the full data url in-page so the report can overlay zones/masks
  // on this exact photo.
  function captureFrame() {
    var video = el("cameraVideo");
    if (!video.videoWidth) return null;
    var canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext("2d").drawImage(video, 0, 0);
    var dataUrl = canvas.toDataURL("image/jpeg", 0.92);
    capturedPhotoDataUrl = dataUrl;
    return dataUrl.split(",")[1] || null;
  }

  el("analyzeBtn").addEventListener("click", function () {
    if (!clientToken || !practitioner) {
      el("cameraNote").textContent = "This check-in needs your personal link — ask your practitioner for your personal link.";
      return;
    }
    if (!photoReady) {
      el("cameraNote").textContent = "Add a photo first — tap “Use my camera” or “Choose a photo”.";
      return;
    }
    analyzeAttempts += 1;

    // First attempt: rehearse the coaching loop through the backend's
    // simulateError hook — a real backend response, no provider call.
    if (analyzeAttempts === 1) {
      setAnalyzing(true);
      postClientScan({ simulateError: "error_lighting_dark" })
        .then(function (res) {
          setAnalyzing(false);
          if (res.body && res.body.errorCode) {
            showCoaching(res.body.errorCode);
          } else {
            el("analyzeStatus").textContent = "Please try again.";
          }
        })
        .catch(function () { failWith("error_network"); });
      return;
    }

    // Second and later attempts: a real photo, a live scan.
    if (photoSource === "camera" && cameraStream) {
      capturedImageBase64 = captureFrame();
      capturedContentType = "image/jpeg";
    }
    if (!capturedImageBase64) {
      el("analyzeStatus").textContent =
        "We need a real photo for your scan — tap “Use my camera” or “Choose a photo” first.";
      return;
    }
    el("coachingCard").hidden = true;
    setAnalyzing(true);
    postClientScan({ imageBase64: capturedImageBase64, contentType: capturedContentType })
      .then(function (res) {
        var body = res.body || {};
        if (body.taskId) {
          el("analyzeStatus").textContent = "Analyzing your photo — this takes just a moment…";
          pollTask(body.taskId, 60);
        } else if (body.status === "complete" && body.result) {
          succeedWith(body.result);
        } else {
          failWith(body.errorCode || "error_analysis_failed");
        }
      })
      .catch(function () { failWith("error_network"); });
  });

  // ---- Report (from the real returned ScanResult) ----
  function focusSentence(key, score) {
    var label = concernLabels[key] || key;
    if (!baseline || !baseline.scores || typeof baseline.scores[key] !== "number" ||
        (currentScan && baseline === currentScan)) {
      var baselineTail;
      if (score < 50) baselineTail = "and a top focus area for daily support.";
      else if (score < 65) baselineTail = "and worth daily support.";
      else if (score < 80) baselineTail = "and holding up well with your current routine.";
      else baselineTail = "and a real strength right now.";
      return label + " is at " + score + " — this scan is your baseline, " + baselineTail;
    }
    var base = baseline.scores[key];
    var delta = score - base;
    var comparison;
    if (delta >= 10) comparison = "much better than your baseline of " + base;
    else if (delta > 0) comparison = "up from your baseline of " + base;
    else if (delta === 0) comparison = "about the same as your baseline of " + base;
    else comparison = "a touch below your baseline of " + base;
    var tail;
    if (score < 50) tail = "and a top focus area for daily support.";
    else if (score < 65) tail = "and still worth daily support.";
    else if (score < 80) tail = "and holding up well with your current routine.";
    else tail = "and a real strength right now.";
    return label + " is at " + score + " — " + comparison + ", " + tail;
  }

  // ---- Report photo overlay (Addendum 2) ----
  // The just-completed report shows the analyzed photo with color-coded
  // facial zones. Data source, in order:
  //   1. the provider's own region-mask PNGs (ScanResult.masks, signed urls,
  //      ~2h expiry) laid over the in-page captured photo — the same masks
  //      the provider's own UI renders;
  //   2. if there are no masks, or every mask image fails to load (expired),
  //      standard zone shapes tinted by the mapped concerns' scores.
  // Timeline stops / stored history have no in-page photo, so the card is
  // skipped there entirely — an expired or missing mask can never break
  // the report, and the scores/text below always remain fully visible.
  var ZONES = [
    { id: "forehead", label: "Forehead", concerns: ["wrinkle"], shapes: [{ left: "31%", top: "6%", width: "38%", height: "20%" }] },
    { id: "underEye", label: "Under-eye", concerns: ["darkCircle", "eyeBag", "tearTrough"], shapes: [{ left: "22%", top: "32%", width: "21%", height: "9%" }, { left: "57%", top: "32%", width: "21%", height: "9%" }] },
    { id: "tZone", label: "T-zone", concerns: ["pore", "oiliness"], shapes: [{ left: "44%", top: "28%", width: "12%", height: "42%" }] },
    { id: "cheeks", label: "Cheeks", concerns: ["redness", "ageSpot"], shapes: [{ left: "13%", top: "44%", width: "28%", height: "24%" }, { left: "59%", top: "44%", width: "28%", height: "24%" }] },
    { id: "lowerFace", label: "Lower face", concerns: ["acne", "texture"], shapes: [{ left: "33%", top: "68%", width: "34%", height: "20%" }] }
  ];
  function severityFor(score) {
    if (typeof score !== "number") return null;
    if (score >= 80) return { name: "Strong", fill: "rgba(74, 140, 74, 0.38)", dot: "#4A8C4A" };
    if (score >= 65) return { name: "Good", fill: "rgba(214, 178, 60, 0.42)", dot: "#D6B23C" };
    if (score >= 50) return { name: "Fair — worth focus", fill: "rgba(224, 122, 58, 0.45)", dot: "#E07A3A" };
    return { name: "Top focus area", fill: "rgba(198, 62, 52, 0.48)", dot: "#C63E34" };
  }
  function zoneScore(zone) {
    var worst = null;
    zone.concerns.forEach(function (key) {
      var s = currentScan.scores[key];
      if (typeof s === "number" && (worst === null || s < worst)) worst = s;
    });
    return worst;
  }
  function renderZoneFallback() {
    var layer = el("zoneLayer");
    layer.innerHTML = "";
    ZONES.forEach(function (zone) {
      var sev = severityFor(zoneScore(zone));
      if (!sev) return;
      zone.shapes.forEach(function (shape) {
        var d = document.createElement("div");
        d.className = "zone-shape";
        d.style.left = shape.left; d.style.top = shape.top;
        d.style.width = shape.width; d.style.height = shape.height;
        d.style.background = sev.fill;
        layer.appendChild(d);
      });
    });
    layer.hidden = false;
    el("reportPhotoNote").textContent = "Zone shapes are tinted by the lowest score in each area. See your full scores below.";
  }
  function renderZoneLegend() {
    var legend = el("zoneLegend");
    legend.innerHTML = "";
    var rail = el("zoneRail");
    if (rail) rail.innerHTML = "";
    ZONES.forEach(function (zone) {
      var score = zoneScore(zone);
      var sev = severityFor(score);
      if (!sev) return;
      var item = document.createElement("li");
      item.className = "zone-legend-item";
      var dot = document.createElement("span");
      dot.className = "zone-dot";
      dot.style.background = sev.dot;
      var text = document.createElement("span");
      text.textContent = zone.label + " — " +
        zone.concerns.map(function (k) { return (concernLabels[k] || k) + " " + currentScan.scores[k]; }).join(", ") +
        " (" + sev.name + ")";
      item.appendChild(dot);
      item.appendChild(text);
      legend.appendChild(item);
      // Reference-style score circle beside the photo (Perfect Corp layout):
      // big number = the zone's lowest concern score, rim tinted by band.
      if (rail) {
        var wrap = document.createElement("div");
        wrap.className = "zone-circle";
        var badge = document.createElement("div");
        badge.className = "zone-circle-badge";
        badge.style.borderColor = sev.dot;
        badge.textContent = score;
        var lab = document.createElement("span");
        lab.className = "zone-circle-label";
        lab.textContent = zone.label;
        wrap.appendChild(badge);
        wrap.appendChild(lab);
        rail.appendChild(wrap);
      }
    });
  }
  function renderReportPhoto() {
    var card = el("reportPhotoCard");
    // No in-page photo for this scan (e.g. a stored history scan opened
    // from the personal link): skip the overlay card, keep the scores.
    if (!capturedPhotoDataUrl || !currentScan) { card.hidden = true; return; }
    card.hidden = false;
    el("reportPhoto").src = capturedPhotoDataUrl;
    renderZoneLegend();
    var maskLayer = el("maskLayer");
    maskLayer.innerHTML = "";
    el("zoneLayer").hidden = true;
    el("zoneLayer").innerHTML = "";
    var masks = currentScan.masks || {};
    // Display-only exclusion: the moisture mask is a diffuse whole-face map
    // (measured 33% of the photo, 3.6x the next-largest mask) that washes
    // out the specific concern areas. Its score still shows in the list;
    // only the photo layer is skipped. (DC, 2026-10-20)
    var MASK_OVERLAY_SKIP = { moisture: true };
    var urls = Object.keys(masks).filter(function (k) { return !!masks[k] && !MASK_OVERLAY_SKIP[k]; });
    if (!urls.length) {
      el("reportPhotoNote").textContent = "";
      renderZoneFallback();
      return;
    }
    el("reportPhotoNote").textContent = "Showing the analysis provider's own region masks on your photo, with zone scores beside it and in the legend below. The broad moisture layer is left off the photo so the specific areas stand out — its score is in the list.";
    var settled = 0, loaded = 0;
    urls.forEach(function (key) {
      var img = document.createElement("img");
      img.className = "mask-img";
      img.alt = "";
      img.setAttribute("aria-hidden", "true");
      img.onload = function () { loaded++; settled++; if (settled === urls.length && loaded === 0) renderZoneFallback(); };
      img.onerror = function () {
        // Expired signed url or a failed mask: drop just this layer; if
        // every mask fails, the score-tinted zone shapes take over.
        if (img.parentNode) img.parentNode.removeChild(img);
        settled++; if (settled === urls.length && loaded === 0) renderZoneFallback();
      };
      img.src = masks[key];
      maskLayer.appendChild(img);
    });
  }

  function renderReport() {
    if (!currentScan) return;
    renderReportPhoto();
    // A pending scan's report is hers to see right away; the note says
    // plainly that it joins the series timeline on acceptance (v2.3).
    el("reportPendingNote").hidden = !currentScan.pending;
    el("reportScanMeta").textContent = currentScan.label + " · " + formatDate(currentScan.timestamp);
    el("reportOverall").textContent = currentScan.overall;
    el("reportRing").style.setProperty("--p", currentScan.overall || 0);
    if (!baseline || baseline === currentScan || timelineScans.length <= 1) {
      el("reportDelta").textContent =
        "Your starting point — this is the scan every visit is measured against.";
    } else {
      var overallDelta = currentScan.overall - baseline.overall;
      el("reportDelta").textContent =
        overallDelta > 0
          ? "+" + overallDelta + " since your baseline (" + baseline.overall + ")"
          : overallDelta < 0
            ? "−" + Math.abs(overallDelta) + " since your baseline (" + baseline.overall + ") — shown as it is"
            : "Same overall score as your baseline (" + baseline.overall + ")";
    }
    el("reportSkinAge").textContent = currentScan.skinAge;
    el("reportSkinType").textContent = currentScan.skinType;

    // Top-3 focus areas: the three lowest scores in the current scan.
    var sorted = CONCERNS.slice().sort(function (a, b) {
      return (currentScan.scores[a.key] || 0) - (currentScan.scores[b.key] || 0);
    });
    var focusWrap = el("focusAreas");
    focusWrap.innerHTML = "";
    sorted.slice(0, 3).forEach(function (concern) {
      var score = currentScan.scores[concern.key];
      if (typeof score !== "number") return;
      var card = document.createElement("div");
      card.className = "focus-card";

      var head = document.createElement("div");
      head.className = "focus-card-head";
      var name = document.createElement("span");
      name.className = "focus-card-name";
      name.textContent = concern.label;
      var scoreEl = document.createElement("span");
      scoreEl.className = "focus-card-score";
      scoreEl.textContent = score + " / 100";
      head.appendChild(name);
      head.appendChild(scoreEl);
      card.appendChild(head);

      var chip = document.createElement("span");
      chip.className = "band-chip";
      chip.textContent = bandFor(score);
      card.appendChild(chip);

      var sentence = document.createElement("p");
      sentence.textContent = focusSentence(concern.key, score);
      card.appendChild(sentence);

      focusWrap.appendChild(card);
    });

    // Compact all-concerns list, in the spec order.
    var list = el("allConcerns");
    list.innerHTML = "";
    CONCERNS.forEach(function (concern) {
      var score = currentScan.scores[concern.key];
      if (typeof score !== "number") return;
      var row = document.createElement("div");
      row.className = "concern-row";

      var nameEl = document.createElement("span");
      nameEl.className = "concern-row-name";
      nameEl.textContent = concern.label;
      var scoreEl2 = document.createElement("span");
      scoreEl2.className = "concern-row-score";
      scoreEl2.textContent = score;
      var bandEl = document.createElement("span");
      bandEl.className = "concern-row-band";
      bandEl.textContent = bandFor(score);
      var track = document.createElement("div");
      track.className = "bar-track";
      var fill = document.createElement("div");
      fill.className = "bar-fill";
      fill.style.width = score + "%";
      track.appendChild(fill);

      row.appendChild(nameEl);
      row.appendChild(scoreEl2);
      row.appendChild(bandEl);
      row.appendChild(track);
      list.appendChild(row);
    });
  }

  el("toTimelineBtn").addEventListener("click", function () { showStep(4); });
  el("timelineBackBtn").addEventListener("click", function () { showStep(3); });

  // ---- Series timeline (built from the client record's scans) ----
  function renderTimeline() {
    var list = el("timelineList");
    list.innerHTML = "";
    timelineScans.forEach(function (scan) {
      var item = document.createElement("li");
      item.className = scan.pending ? "timeline-stop timeline-stop-pending" : "timeline-stop";

      var label = document.createElement("p");
      label.className = "timeline-stop-label";
      label.textContent = scan.label;
      var date = document.createElement("p");
      date.className = "timeline-stop-date";
      date.textContent = formatDate(scan.timestamp);
      var score = document.createElement("p");
      score.className = "timeline-stop-score";
      score.textContent = "Overall " + scan.overall + " · Skin age " + scan.skinAge + " · " + scan.skinType;

      var track = document.createElement("div");
      track.className = "bar-track timeline-bar";
      var fill = document.createElement("div");
      fill.className = "bar-fill";
      fill.style.width = (scan.overall || 0) + "%";
      track.appendChild(fill);

      item.appendChild(label);
      item.appendChild(date);
      item.appendChild(score);
      item.appendChild(track);
      if (scan.pending) {
        var badge = document.createElement("p");
        badge.className = "pending-badge";
        badge.textContent = "Pending practitioner review — this scan joins your series once " +
          practitionerFirstName() + " accepts it.";
        item.appendChild(badge);
      }
      list.appendChild(item);
    });

    // Deltas vs the first scan — accepted scans only (v2.3): a pending
    // scan never moves the trend numbers.
    var trendBase = acceptedScans.length ? acceptedScans[0] : null;
    var trendNow = acceptedScans.length ? acceptedScans[acceptedScans.length - 1] : null;
    var hasDeltas = acceptedScans.length >= 2 && trendBase && trendNow;
    el("deltaSection").hidden = !hasDeltas;
    el("baselineNote").hidden = acceptedScans.length !== 1;
    if (hasDeltas) {
      el("deltaHint").textContent = trendNow.label +
        " compared with your baseline scan. A minus means that score is a little lower than at the start — we show it as it is.";
      el("deltaNowHeader").textContent = trendNow.label;

      var focusKeys = (plan && plan.focus)
        ? plan.focus.map(function (f) { return f.concern; })
        : [];
      var ordered = CONCERNS.slice().sort(function (a, b) {
        var aFocus = focusKeys.indexOf(a.key) >= 0 ? 0 : 1;
        var bFocus = focusKeys.indexOf(b.key) >= 0 ? 0 : 1;
        return aFocus - bFocus;
      });
      var body = el("deltaTableBody");
      body.innerHTML = "";
      ordered.forEach(function (concern) {
        var base = trendBase.scores[concern.key];
        var now = trendNow.scores[concern.key];
        if (typeof base !== "number" || typeof now !== "number") return;
        var delta = now - base;

        var row = document.createElement("tr");
        var nameCell = document.createElement("td");
        nameCell.textContent = concern.label;
        if (focusKeys.indexOf(concern.key) >= 0) {
          var tag = document.createElement("span");
          tag.className = "focus-tag";
          tag.textContent = "Plan focus";
          nameCell.appendChild(tag);
        }
        var baseCell = document.createElement("td");
        baseCell.className = "num";
        baseCell.textContent = base;
        var nowCell = document.createElement("td");
        nowCell.className = "num";
        nowCell.textContent = now;
        var deltaCell = document.createElement("td");
        deltaCell.className = "num " + (delta > 0 ? "delta-up" : delta < 0 ? "delta-down" : "delta-flat");
        if (delta > 0) deltaCell.textContent = "+" + delta;
        else if (delta < 0) deltaCell.textContent = "−" + Math.abs(delta);
        else deltaCell.textContent = "No change";

        row.appendChild(nameCell);
        row.appendChild(baseCell);
        row.appendChild(nowCell);
        row.appendChild(deltaCell);
        body.appendChild(row);
      });
    }

    // Plan card, rendered from the plan JSON when present.
    var hasPlan = !!plan && (
      plan.seriesName || plan.focus || plan.regimen || plan.products || plan.service
    );
    el("planCard").hidden = !hasPlan;
    if (hasPlan) {
      el("planSeries").textContent = plan.seriesName
        ? plan.seriesName + (plan.sessions ? " — " + plan.sessions + " sessions" : "")
        : "";
      el("planSeries").hidden = !plan.seriesName;

      var planService = plan.service;
      el("planService").hidden = !planService;
      if (planService) {
        el("planService").textContent =
          "Series treatment: " + (planService.name || "") + " — " +
          formatPrice(planService.price) +
          (planService.unit ? " " + planService.unit : "");
      }

      var focus = plan.focus || [];
      el("planFocusSection").hidden = !focus.length;
      var focusWrap = el("planFocus");
      focusWrap.innerHTML = "";
      focus.forEach(function (f) {
        var wrap = document.createElement("div");
        wrap.className = "plan-focus-item";
        var title = document.createElement("strong");
        title.textContent = concernLabels[f.concern] || f.concern || "";
        var note = document.createElement("span");
        note.textContent = f.note || "";
        wrap.appendChild(title);
        wrap.appendChild(note);
        focusWrap.appendChild(wrap);
      });

      var regimen = plan.regimen || {};
      var hasRegimen = !!(regimen.am || regimen.pm);
      el("planRegimenSection").hidden = !hasRegimen;
      el("planAmRow").hidden = !regimen.am;
      el("planPmRow").hidden = !regimen.pm;
      el("planAm").textContent = regimen.am || "";
      el("planPm").textContent = regimen.pm || "";

      var products = plan.products || [];
      el("planProductsSection").hidden = !products.length;
      var productList = el("planProducts");
      productList.innerHTML = "";
      var total = 0;
      var hasPrices = false;
      products.forEach(function (product) {
        if (!product) return;
        if (typeof product.price === "number" || product.price) hasPrices = true;
        total += priceValue(product.price);
        var item = document.createElement("li");
        var nameEl = document.createElement("span");
        nameEl.textContent = product.name || "";
        var priceEl = document.createElement("span");
        priceEl.textContent = formatPrice(product.price);
        item.appendChild(nameEl);
        item.appendChild(priceEl);
        productList.appendChild(item);
      });
      el("planProductsTotal").textContent = hasPrices ? "Total " + formatPrice(total) : "";
      el("planProductsTotal").hidden = !hasPrices;
    }

    // Book next session — only when the practitioner has a booking link.
    var bookingLink = practitioner && practitioner.bookingLink;
    el("nextCard").hidden = !bookingLink;
    if (bookingLink) {
      el("nextCardText").textContent =
        "Ready for your next session? Book it with " +
        (practitioner.practiceName || "your practitioner") + ".";
      var booking = el("bookingLink");
      booking.href = bookingLink;
      booking.textContent = "Book next session";
    }
  }


  // ---- Client login (v2.2) — OPTIONAL, recovery only ----
  // The personal link remains the credential; nothing in the scan flow
  // needs an account, and a client who never creates one loses nothing.
  // A login only lets her sign back in on a new device without the link.
  function postJson(path, payload) {
    return fetch(apiUrl(path), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {})
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (body) {
        return { httpStatus: r.status, body: body };
      });
    });
  }

  function renderAccountCard() {
    var card = el("accountCard");
    if (!card) return;
    var dismissed = false;
    try {
      dismissed = window.sessionStorage.getItem("estiseries.accountOfferDismissed") === "1";
    } catch (e) {}
    el("accountCreate").hidden = !!clientAccount;
    el("accountState").hidden = !clientAccount;
    if (!clientAccount) {
      card.hidden = dismissed;
      return;
    }
    card.hidden = false;
    if (clientAccount.emailVerified) {
      el("accountStateText").textContent =
        "Login on file for " + clientAccount.email + " — verified, so you can sign back in on any device.";
      el("accountResendBtn").hidden = true;
    } else {
      el("accountStateText").textContent =
        "Login created for " + clientAccount.email + ". Verify your email to enable account recovery.";
      el("accountResendBtn").hidden = false;
    }
  }

  function showSigninView() {
    steps.forEach(function (id) { el(id).hidden = true; });
    el("practiceMark").hidden = true;
    el("progressWrap").hidden = true;
    el("step-signin").hidden = false;
    document.title = "Sign in — EstiSeries";
  }

  function wireAccountUi() {
    el("accountDismissBtn").addEventListener("click", function () {
      try {
        window.sessionStorage.setItem("estiseries.accountOfferDismissed", "1");
      } catch (e) {}
      el("accountCard").hidden = true;
    });
    el("accountCreateBtn").addEventListener("click", function () {
      var email = el("accountEmail").value.trim();
      var password = el("accountPassword").value;
      var status = el("accountStatus");
      if (!email || password.length < 8) {
        status.textContent = "Enter your email and a password of at least 8 characters.";
        return;
      }
      status.textContent = "Creating your login…";
      postJson("/api/clients/" + encodeURIComponent(clientToken) + "/account", {
        email: email,
        password: password
      })
        .then(function (res) {
          if (res.httpStatus === 200) {
            clientAccount = { email: email, emailVerified: false };
            renderAccountCard();
            el("accountStateStatus").textContent =
              "Login created — check your email for a verification link.";
            return;
          }
          if (res.httpStatus === 409) {
            status.textContent = "That email already has a login — use Sign in instead.";
            return;
          }
          status.textContent =
            (res.body && res.body.message) || "We could not create that login just now.";
        })
        .catch(function () {
          status.textContent = "We could not create that login just now.";
        });
    });
    el("accountForgotBtn").addEventListener("click", function () {
      var email = el("accountEmail").value.trim();
      var status = el("accountStatus");
      if (!email) {
        status.textContent = "Enter your email above first, then tap Forgot password.";
        return;
      }
      postJson("/api/auth/forgot-password", { email: email })
        .then(function () {
          status.textContent = "If that email has a login, a reset link is on its way.";
        })
        .catch(function () {
          status.textContent = "We could not send that just now.";
        });
    });
    el("accountResendBtn").addEventListener("click", function () {
      if (!clientAccount) return;
      postJson("/api/auth/resend-verification", { email: clientAccount.email })
        .then(function () {
          el("accountStateStatus").textContent = "Verification email sent — check your inbox.";
        })
        .catch(function () {
          el("accountStateStatus").textContent = "We could not send that just now.";
        });
    });
    el("publicSigninLink").addEventListener("click", function () {
      window.location.href = "./?signin=1";
    });
    el("signinBtn").addEventListener("click", function () {
      var email = el("signinEmail").value.trim();
      var password = el("signinPassword").value;
      var status = el("signinStatus");
      if (!email || !password) {
        status.textContent = "Enter your email and password.";
        return;
      }
      status.textContent = "Signing in…";
      postJson("/api/clients/signin", { email: email, password: password })
        .then(function (res) {
          if (res.httpStatus !== 200 || !res.body.clientToken) {
            status.textContent =
              "That email and password don't match a login. Your personal link works too.";
            return;
          }
          clientToken = res.body.clientToken;
          try {
            window.localStorage.setItem("estiseries.clientToken", clientToken);
          } catch (e) {}
          try {
            window.history.replaceState({}, "", window.location.pathname);
          } catch (e) {}
          el("step-signin").hidden = true;
          return fetchClientRecord().then(function (rec) {
            if (rec.httpStatus !== 200 || !rec.body || !rec.body.practitioner) {
              status.textContent = "Signed in, but we could not load your series just now.";
              el("step-signin").hidden = false;
              return;
            }
            applyClientRecord(rec.body);
            showPersonalWelcome();
            if (currentScan) {
              renderReport();
              renderTimeline();
            }
          });
        })
        .catch(function () {
          status.textContent = "We could not sign you in just now.";
        });
    });
    el("signinForgotBtn").addEventListener("click", function () {
      var email = el("signinEmail").value.trim();
      var status = el("signinStatus");
      if (!email) {
        status.textContent = "Enter your email above first, then tap Forgot password.";
        return;
      }
      postJson("/api/auth/forgot-password", { email: email })
        .then(function () {
          status.textContent = "If that email has a login, a reset link is on its way.";
        })
        .catch(function () {
          status.textContent = "We could not send that just now.";
        });
    });
  }
  wireAccountUi();

  // ---- Boot: resolve the client token, if any ----
  if (signinRequested) {
    showSigninView();
  } else if (!clientToken) {
    showPublicLanding();
  } else {
    // Until the token resolves, keep the welcome step neutral.
    el("personalWelcome").hidden = true;
    el("publicWelcome").hidden = true;
    el("invalidWelcome").hidden = true;
    el("tryCard").hidden = true;
    showStep(0);
    el("progressWrap").hidden = true;
    fetchClientRecord()
      .then(function (res) {
        if (res.httpStatus === 404) {
          if (!hadLinkParam) {
            // A stored token from an earlier sign-in no longer resolves:
            // forget it and land softly — no scolding about a link she
            // never used.
            try {
              window.localStorage.removeItem("estiseries.clientToken");
            } catch (e) {}
            showPublicLanding();
            return;
          }
          showInvalidLink("This link isn't active — ask your practitioner for your personal link.");
          return;
        }
        if (res.httpStatus !== 200 || !res.body || !res.body.practitioner) {
          showInvalidLink("We could not load this link just now — ask your practitioner for your personal link, or try a real scan below.");
          return;
        }
        applyClientRecord(res.body);
        showPersonalWelcome();
        if (currentScan) {
          renderReport();
          renderTimeline();
        }
      })
      .catch(function () {
        showInvalidLink("We could not load this link just now — ask your practitioner for your personal link, or try a real scan below.");
      });
  }
})();
