// SkinSeries client web flow — plain script, no build step, no modules.
// Data comes from window.DEMO_DATA (demo-data.js, mirroring the seeded demo data).
(function () {
  "use strict";

  var data = window.DEMO_DATA;
  var practice = data.practice;
  var client = data.clients[0];
  var scans = client.scans;
  var baseline = scans[0];
  var latest = scans[scans.length - 1];
  var plan = client.plan;

  var concernLabels = {};
  data.concerns.forEach(function (c) { concernLabels[c.key] = c.label; });

  var firstName = practice.practitioner.split(" ")[0];

  // ---- Score bands (per spec): higher is healthier, 1-100 ----
  function bandFor(score) {
    if (score >= 80) return "Strong";
    if (score >= 65) return "Good";
    if (score >= 50) return "Fair — worth focus";
    return "A top focus area";
  }

  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  function formatDate(iso) {
    var parts = iso.split("-");
    var month = MONTHS[parseInt(parts[1], 10) - 1];
    var day = parseInt(parts[2], 10);
    return month + " " + day + ", " + parts[0];
  }
  function formatDateShort(iso) {
    var parts = iso.split("-");
    return MONTHS[parseInt(parts[1], 10) - 1] + " " + parseInt(parts[2], 10);
  }

  function el(id) { return document.getElementById(id); }

  // ---- Step navigation ----
  var steps = ["step-welcome", "step-consent", "step-capture", "step-report", "step-timeline"];
  var stepNames = ["Welcome", "Consent", "Photo", "Your report", "Series timeline"];
  var currentStep = 0;
  function showStep(index) {
    currentStep = index;
    steps.forEach(function (id, i) { el(id).hidden = i !== index; });
    el("progressLabel").textContent = "Step " + (index + 1) + " of " + steps.length + " — " + stepNames[index];
    window.scrollTo(0, 0);
  }

  // ---- Branding from the practice record ----
  el("practiceName").textContent = practice.name;
  el("practiceTagline").textContent = practice.tagline;
  document.title = "Skin check-in — " + practice.name;
  if (practice.accent) {
    document.documentElement.style.setProperty("--terra", practice.accent);
  }

  el("startBtn").addEventListener("click", function () { showStep(1); });

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
  // Real backend contract (backend/server.js):
  //   GET  {backend}/health            -> { ok, mode: "demo" | "live" }
  //   POST {backend}/api/scans         -> one of:
  //     { demoStage: "session6" }      demo mode: seeded result, returned
  //                                    inline as { status:"complete", result }
  //     { imageBase64, contentType }   live mode: { taskId, status:"running" },
  //                                    then poll GET /api/scans/<taskId>
  //     { simulateError: "<code>" }    any mode: HTTP 422 { errorCode } —
  //                                    the backend's coaching-rehearsal hook
  //   Error bodies carry a YouCam-style errorCode; the photo-quality codes
  //   map to the coaching card, everything else to a plain status message:
  //     error_lighting_dark       -> lighting tip below
  //     error_src_face_too_small -> move-closer tip below
  // The backend lives on the same host as this page, port 8787 (this page
  // is served statically on another port). window.BACKEND_BASE_URL can
  // override the base before this script loads.
  var BACKEND_BASE = window.BACKEND_BASE_URL ||
    (location.protocol + "//" + location.hostname + ":8787");
  var COACHING = {
    error_lighting_dark: "It's a bit dark — face a window or turn on a brighter light, then try again.",
    error_src_face_too_small: "Move a little closer so your face fills the frame."
  };
  var ERROR_MESSAGES = {
    error_upload_failed: "That photo could not be processed — try a clearer, front-facing photo in bright light.",
    error_analysis_failed: "The analysis did not finish — please try again with a clear, front-facing photo.",
    error_network: "We could not reach the analysis service — check the connection and try again.",
    error_timeout: "The analysis is taking longer than usual — please try again.",
    error_task_not_found: "That scan could not be found — please try again."
  };
  function messageForError(code) {
    return ERROR_MESSAGES[code] ||
      "Something went wrong with that photo (" + code + ") — please try again.";
  }

  // Backend mode, learned from /health. Stays null when the backend cannot
  // be reached at all — the flow then falls back to the scripted demo
  // behavior below so the check-in still works end-to-end offline.
  var backendMode = null;
  var healthReady = fetch(BACKEND_BASE + "/health")
    .then(function (r) { return r.json(); })
    .then(function (body) {
      if (body && (body.mode === "demo" || body.mode === "live")) {
        backendMode = body.mode;
        if (body.mode === "live") el("modeBadge").textContent = "Live mode";
      }
    })
    .catch(function () { backendMode = null; });

  // The scan this check-in produces. Starts as the seeded latest scan; a
  // finished backend analysis replaces its numbers (demo mode) or appends a
  // new stop (live mode) — see succeedWith().
  var timelineScans = scans.slice();
  var currentScan = latest;

  var analyzeAttempts = 0;
  var cameraStream = null;
  var photoReady = false;
  var photoSource = null; // "camera" | "demo"
  var capturedImageBase64 = null;

  function setPhotoReady(ready, note) {
    photoReady = ready;
    if (note) el("cameraNote").textContent = note;
  }

  el("demoPhotoBtn").addEventListener("click", function () {
    stopCamera();
    photoSource = "demo";
    capturedImageBase64 = null;
    el("cameraVideo").hidden = true;
    el("facePlaceholder").hidden = false;
    el("facePlaceholderText").textContent = "Demo photo ready";
    setPhotoReady(true, "Demo photo loaded — this is the photo we will use for your skin analysis.");
    el("coachingCard").hidden = true;
    el("analyzeStatus").textContent = "";
  });

  el("cameraBtn").addEventListener("click", function () {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setPhotoReady(photoReady, "Camera is not available on this device — the demo photo works just as well for this check-in.");
      return;
    }
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false })
      .then(function (stream) {
        cameraStream = stream;
        photoSource = "camera";
        capturedImageBase64 = null;
        var video = el("cameraVideo");
        video.srcObject = stream;
        video.hidden = false;
        el("facePlaceholder").hidden = true;
        setPhotoReady(true, "Camera on — hold still, look straight at the camera, then tap Analyze my photo.");
      })
      .catch(function () {
        setPhotoReady(photoReady, "We could not open the camera here — the demo photo works just as well for this check-in.");
      });
  });

  function stopCamera() {
    if (cameraStream) {
      cameraStream.getTracks().forEach(function (track) { track.stop(); });
      cameraStream = null;
    }
  }

  el("captureBackBtn").addEventListener("click", function () { stopCamera(); showStep(1); });

  // ---- Analysis run ----

  function setAnalyzing(on) {
    var button = el("analyzeBtn");
    button.disabled = on;
    button.textContent = on ? "Analyzing…" : "Analyze my photo";
    el("analyzeStatus").textContent = on
      ? "Analyzing your photo — this takes just a moment…"
      : "";
  }

  function showCoaching(errorCode) {
    el("coachingText").textContent =
      COACHING[errorCode] || messageForError(errorCode);
    el("coachingCard").hidden = false;
    el("analyzeBtn").textContent = "Try again";
    el("coachingCard").scrollIntoView({ block: "nearest" });
  }

  // A failure the client can act on: photo-quality codes get the coaching
  // card; anything else gets a plain status line. Either way she can retry.
  function failWith(errorCode) {
    setAnalyzing(false);
    if (COACHING[errorCode]) {
      showCoaching(errorCode);
    } else {
      el("coachingCard").hidden = true;
      el("analyzeStatus").textContent = messageForError(errorCode);
      el("analyzeBtn").textContent = "Try again";
    }
  }

  function postScan(body) {
    return fetch(BACKEND_BASE + "/api/scans", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    }).then(function (r) {
      return r.json().catch(function () { return {}; });
    });
  }

  function pollTask(taskId, triesLeft) {
    return fetch(BACKEND_BASE + "/api/scans/" + encodeURIComponent(taskId))
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
        setTimeout(function () { pollTask(taskId, triesLeft - 1); }, 1500);
      })
      .catch(function () { failWith("error_network"); });
  }

  function todayIso() {
    var d = new Date();
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  }

  function succeedWith(result) {
    stopCamera();
    setAnalyzing(false);
    el("coachingCard").hidden = true;
    if (backendMode === "live") {
      // A real new scan: it becomes the newest stop on her timeline.
      currentScan = {
        label: "New scan",
        date: todayIso(),
        stage: "live",
        sessionNumber: timelineScans.length + 1,
        overall: result.overall,
        skinAge: result.skinAge,
        skinType: result.skinType,
        scores: result.scores
      };
      timelineScans = timelineScans.concat([currentScan]);
    } else {
      // Demo mode: the returned result is this check-in's stage result —
      // same stop, the backend's numbers.
      currentScan = {
        label: latest.label,
        date: latest.date,
        stage: latest.stage,
        sessionNumber: latest.sessionNumber,
        overall: result.overall,
        skinAge: result.skinAge,
        skinType: result.skinType,
        scores: result.scores
      };
      timelineScans = scans.slice();
      timelineScans[timelineScans.length - 1] = currentScan;
    }
    renderReport();
    renderTimeline();
    showStep(3);
  }

  // Offline fallback — the original scripted demo behavior, kept for when
  // no backend answers at all: attempt 1 coaches on lighting, attempt 2
  // renders the seeded result.
  function scriptedAttempt() {
    if (analyzeAttempts === 1) {
      showCoaching("error_lighting_dark");
      return;
    }
    el("coachingCard").hidden = true;
    setAnalyzing(true);
    setTimeout(function () {
      stopCamera();
      setAnalyzing(false);
      renderReport();
      renderTimeline();
      showStep(3);
    }, 1400);
  }

  // Grab the current camera frame as base64 JPEG (no data: prefix).
  function captureFrame() {
    var video = el("cameraVideo");
    if (!video.videoWidth) return null;
    var canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext("2d").drawImage(video, 0, 0);
    var dataUrl = canvas.toDataURL("image/jpeg", 0.92);
    return dataUrl.split(",")[1] || null;
  }

  el("analyzeBtn").addEventListener("click", function () {
    if (!photoReady) {
      el("cameraNote").textContent = "Add a photo first — tap \u201CUse a demo photo instead\u201D or \u201CUse my camera\u201D.";
      return;
    }
    if (photoSource === "camera" && cameraStream) {
      capturedImageBase64 = captureFrame();
    }
    analyzeAttempts += 1;
    healthReady.then(function () {
      if (!backendMode) {
        scriptedAttempt();
        return;
      }
      // First attempt: rehearse the coaching loop through the backend's
      // simulateError hook (served in every mode) — the preserved demo
      // behavior, now driven by a real backend response.
      if (analyzeAttempts === 1) {
        setAnalyzing(true);
        postScan({ simulateError: "error_lighting_dark" })
          .then(function (body) {
            setAnalyzing(false);
            if (body.errorCode) showCoaching(body.errorCode);
            else scriptedAttempt();
          })
          .catch(function () {
            setAnalyzing(false);
            backendMode = null;
            scriptedAttempt();
          });
        return;
      }
      el("coachingCard").hidden = true;
      if (backendMode === "live") {
        if (!capturedImageBase64) {
          el("analyzeStatus").textContent =
            "In live mode the analysis needs a real photo — tap \u201CUse my camera\u201D and take your photo.";
          return;
        }
        setAnalyzing(true);
        postScan({ imageBase64: capturedImageBase64, contentType: "image/jpeg" })
          .then(function (body) {
            if (body.taskId) {
              pollTask(body.taskId, 40);
            } else if (body.status === "complete" && body.result) {
              succeedWith(body.result);
            } else {
              failWith(body.errorCode || "error_analysis_failed");
            }
          })
          .catch(function () { failWith("error_network"); });
        return;
      }
      // Demo mode: the backend serves the seeded result for this stage —
      // a camera photo, when present, is carried by the stage contract.
      setAnalyzing(true);
      postScan({ demoStage: latest.stage })
        .then(function (body) {
          if (body.status === "complete" && body.result) {
            succeedWith(body.result);
          } else {
            failWith(body.errorCode || "error_analysis_failed");
          }
        })
        .catch(function () { failWith("error_network"); });
    });
  });

  // ---- Report (from the latest scan) ----
  function focusSentence(key, score) {
    var label = concernLabels[key];
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

  function renderReport() {
    el("reportScanMeta").textContent = currentScan.label + " · " + formatDate(currentScan.date);
    el("reportOverall").textContent = currentScan.overall;
    el("reportSkinAge").textContent = currentScan.skinAge;
    el("reportSkinType").textContent = currentScan.skinType;

    // Top-3 focus areas: the three lowest scores in the current scan.
    var sorted = data.concerns.slice().sort(function (a, b) {
      return currentScan.scores[a.key] - currentScan.scores[b.key];
    });
    var focusWrap = el("focusAreas");
    focusWrap.innerHTML = "";
    sorted.slice(0, 3).forEach(function (concern) {
      var score = currentScan.scores[concern.key];
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
    data.concerns.forEach(function (concern) {
      var score = currentScan.scores[concern.key];
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

  // ---- Series timeline ----
  function renderTimeline() {
    el("deltaHint").textContent = currentScan.label +
      " compared with your baseline scan. A minus means that score is a little lower than at the start — we show it as it is.";
    el("deltaNowHeader").textContent = currentScan.label;
    var list = el("timelineList");
    list.innerHTML = "";
    timelineScans.forEach(function (scan) {
      var item = document.createElement("li");
      item.className = "timeline-stop";

      var label = document.createElement("p");
      label.className = "timeline-stop-label";
      label.textContent = scan.label;
      var date = document.createElement("p");
      date.className = "timeline-stop-date";
      date.textContent = formatDate(scan.date);
      var score = document.createElement("p");
      score.className = "timeline-stop-score";
      score.textContent = "Overall " + scan.overall + " · Skin age " + scan.skinAge + " · " + scan.skinType;

      item.appendChild(label);
      item.appendChild(date);
      item.appendChild(score);
      list.appendChild(item);
    });

    // Per-concern change vs baseline: plan focus concerns first, then the
    // rest — every concern is shown, including any that went down.
    var focusKeys = plan.focus.map(function (f) { return f.concern; });
    var ordered = data.concerns.slice().sort(function (a, b) {
      var aFocus = focusKeys.indexOf(a.key) >= 0 ? 0 : 1;
      var bFocus = focusKeys.indexOf(b.key) >= 0 ? 0 : 1;
      return aFocus - bFocus;
    });
    var body = el("deltaTableBody");
    body.innerHTML = "";
    ordered.forEach(function (concern) {
      var base = baseline.scores[concern.key];
      var now = currentScan.scores[concern.key];
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

    // Plan card, shared by the practitioner.
    el("planSeries").textContent = plan.seriesName + " — " + plan.sessions + " sessions";
    var focusWrap = el("planFocus");
    focusWrap.innerHTML = "";
    plan.focus.forEach(function (f) {
      var wrap = document.createElement("div");
      wrap.className = "plan-focus-item";
      var title = document.createElement("strong");
      title.textContent = concernLabels[f.concern] || f.concern;
      var note = document.createElement("span");
      note.textContent = f.note;
      wrap.appendChild(title);
      wrap.appendChild(note);
      focusWrap.appendChild(wrap);
    });
    el("planAm").textContent = plan.regimen.am;
    el("planPm").textContent = plan.regimen.pm;

    var productList = el("planProducts");
    productList.innerHTML = "";
    var total = 0;
    plan.productIds.forEach(function (id) {
      var product = null;
      data.products.forEach(function (p) { if (p.id === id) product = p; });
      if (!product) return;
      total += product.price;
      var item = document.createElement("li");
      var nameEl = document.createElement("span");
      nameEl.textContent = product.name;
      var priceEl = document.createElement("span");
      priceEl.textContent = "$" + product.price;
      item.appendChild(nameEl);
      item.appendChild(priceEl);
      productList.appendChild(item);
    });
    el("planProductsTotal").textContent = "Total $" + total;

    var booking = el("bookingLink");
    booking.href = practice.bookingUrl;
    booking.textContent = "Book your next visit";
  }

  showStep(0);
})();
