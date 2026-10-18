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
  // Mock of the live analysis contract, used in demo mode:
  // In live mode this step POSTs the photo to the backend at /api/scans and
  // then polls that scan until it finishes. A finished scan returns the
  // result shape from the spec; a photo that cannot be read returns an
  // error code instead. Error codes map to plain coaching messages:
  //   error_lighting_dark       -> lighting tip below
  //   error_src_face_too_small -> move-closer tip below
  var COACHING = {
    error_lighting_dark: "It's a bit dark — face a window or turn on a brighter light, then try again.",
    error_src_face_too_small: "Move a little closer so your face fills the frame."
  };
  // Demo behavior: attempt 1 returns error_lighting_dark, attempt 2 succeeds.
  var analyzeAttempts = 0;
  var cameraStream = null;
  var photoReady = false;

  function setPhotoReady(ready, note) {
    photoReady = ready;
    if (note) el("cameraNote").textContent = note;
  }

  el("demoPhotoBtn").addEventListener("click", function () {
    stopCamera();
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

  el("analyzeBtn").addEventListener("click", function () {
    if (!photoReady) {
      el("cameraNote").textContent = "Add a photo first — tap \u201CUse a demo photo instead\u201D or \u201CUse my camera\u201D.";
      return;
    }
    analyzeAttempts += 1;
    var coachingCard = el("coachingCard");
    var status = el("analyzeStatus");
    var button = el("analyzeBtn");

    if (analyzeAttempts === 1) {
      // Simulated first-attempt error: error_lighting_dark.
      el("coachingText").textContent = COACHING.error_lighting_dark;
      coachingCard.hidden = false;
      status.textContent = "";
      button.textContent = "Try again";
      coachingCard.scrollIntoView({ block: "nearest" });
      return;
    }

    coachingCard.hidden = true;
    button.disabled = true;
    button.textContent = "Analyzing…";
    status.textContent = "Analyzing your photo — this takes just a moment…";
    setTimeout(function () {
      stopCamera();
      button.disabled = false;
      button.textContent = "Analyze my photo";
      status.textContent = "";
      renderReport();
      renderTimeline();
      showStep(3);
    }, 1400);
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
    el("reportScanMeta").textContent = latest.label + " · " + formatDate(latest.date);
    el("reportOverall").textContent = latest.overall;
    el("reportSkinAge").textContent = latest.skinAge;
    el("reportSkinType").textContent = latest.skinType;

    // Top-3 focus areas: the three lowest scores in the latest scan.
    var sorted = data.concerns.slice().sort(function (a, b) {
      return latest.scores[a.key] - latest.scores[b.key];
    });
    var focusWrap = el("focusAreas");
    focusWrap.innerHTML = "";
    sorted.slice(0, 3).forEach(function (concern) {
      var score = latest.scores[concern.key];
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
      var score = latest.scores[concern.key];
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
    var list = el("timelineList");
    list.innerHTML = "";
    scans.forEach(function (scan) {
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
      var now = latest.scores[concern.key];
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
