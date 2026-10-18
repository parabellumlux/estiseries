'use strict';

// SkinSeries backend proxy — the only component that holds the YouCam API key.
// Zero-dependency Node.js (>= 18): built-in `http` plus the global `fetch`.
//
// Modes:
//   demo (default) — no YOUCAM_API_KEY in the environment. Serves seeded results
//     from ../assets/demo/demo_data.json (read once at startup). Never touches
//     the network.
//   live — YOUCAM_API_KEY is set. Implements the real YouCam (Perfect Corp YCE)
//     async flow against https://yce-api-01.makeupar.com:
//       1. POST /s2s/v2.0/file/skin-analysis   -> pre-signed upload URL + file id
//       2. PUT the image bytes to that URL
//       3. POST /s2s/v2.0/task/skin-analysis   -> task_id (SD action list)
//       4. GET  /s2s/v2.0/task/skin-analysis/<task_id> until complete
//       5. Map the response into the shared ScanResult shape from SPEC.md
//
// IMPORTANT: the live path is written to the published YouCam docs but is
// UNTESTED end-to-end until a real API key exists. The response mapper is
// deliberately defensive about field names for that reason. Nothing here is
// faked — when a key is present the requests really go to YouCam.

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const YOUCAM_BASE = 'https://yce-api-01.makeupar.com';
const DEMO_DATA_PATH = path.join(__dirname, '..', 'assets', 'demo', 'demo_data.json');
const DEMO_STAGES = ['baseline', 'session3', 'session6'];
// Error codes the client coaching loop develops against; mirrors the YouCam
// error surface so the same client code works in demo and live modes.
const SIMULATED_ERROR_CODES = ['error_lighting_dark', 'error_src_face_too_small'];
const MAX_BODY_BYTES = 25 * 1024 * 1024; // base64 photos are large
const REQUEST_TIMEOUT_MS = 30000;
const UPLOAD_TIMEOUT_MS = 60000;
const POLL_INTERVAL_MS = 2000;
const MAX_POLL_ATTEMPTS = 150; // ~5 minutes upstream, then report an error

// SD (standard-definition) concern list sent with the task request. Simultaneous
// SD + HD concern parameters are not supported by the API, so this stays SD.
const SD_ACTIONS = [
  'skin_type',
  'wrinkle',
  'pore',
  'texture',
  'acne',
  'oiliness',
  'radiance',
  'eye_bag',
  'age_spot',
  'dark_circle_v2',
  'droopy_upper_eyelid',
  'droopy_lower_eyelid',
  'firmness',
  'moisture',
  'redness',
  'tear_trough',
];

// YouCam item type -> shared ScanResult concern key (SPEC.md).
const ITEM_TYPE_TO_CONCERN = {
  wrinkle: 'wrinkle',
  pore: 'pore',
  texture: 'texture',
  acne: 'acne',
  oiliness: 'oiliness',
  radiance: 'radiance',
  eye_bag: 'eyeBag',
  age_spot: 'ageSpot',
  dark_circle: 'darkCircle',
  dark_circle_v2: 'darkCircle',
  droopy_upper_eyelid: 'droopyUpperEyelid',
  droopy_lower_eyelid: 'droopyLowerEyelid',
  firmness: 'firmness',
  moisture: 'moisture',
  redness: 'redness',
  tear_trough: 'tearTrough',
};

// Minimal embedded ScanResult used only if the seeded demo file cannot be read,
// so demo mode still works end-to-end (values are the SPEC.md example shape).
const FALLBACK_SCAN_RESULT = Object.freeze({
  overall: 61,
  skinAge: 47,
  skinType: 'Combination',
  scores: {
    wrinkle: 63,
    pore: 60,
    texture: 57,
    acne: 55,
    oiliness: 66,
    radiance: 52,
    eyeBag: 59,
    ageSpot: 71,
    darkCircle: 54,
    droopyUpperEyelid: 78,
    droopyLowerEyelid: 80,
    firmness: 64,
    moisture: 42,
    redness: 58,
    tearTrough: 69,
  },
});

// ---------------------------------------------------------------------------
// Environment (.env support without dependencies)
// ---------------------------------------------------------------------------

// Loads backend/.env if present, without overriding variables already in the
// environment and without ever printing values. Real .env files are gitignored;
// .env.example is the committed template.
function loadDotEnv() {
  try {
    const text = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      let value = trimmed.slice(eq + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      if (key && !(key in process.env)) process.env[key] = value;
    }
  } catch (_) {
    // No .env file is perfectly fine — demo mode needs nothing.
  }
}

loadDotEnv();

const API_KEY =
  process.env.YOUCAM_API_KEY && process.env.YOUCAM_API_KEY.trim()
    ? process.env.YOUCAM_API_KEY.trim()
    : null;
const MODE = API_KEY ? 'live' : 'demo';
const PORT = Number.parseInt(process.env.PORT || '', 10) || 8787;

// ---------------------------------------------------------------------------
// Demo data (read once at startup)
// ---------------------------------------------------------------------------

function toScanResult(scan) {
  return {
    overall: scan.overall,
    skinAge: scan.skinAge,
    skinType: scan.skinType,
    scores: Object.assign({}, scan.scores),
  };
}

function loadDemoScans() {
  try {
    const data = JSON.parse(fs.readFileSync(DEMO_DATA_PATH, 'utf8'));
    const scans = (data.clients && data.clients[0] && data.clients[0].scans) || [];
    const byStage = {};
    for (const scan of scans) {
      if (scan && typeof scan.stage === 'string') byStage[scan.stage] = toScanResult(scan);
    }
    if (!DEMO_STAGES.some((stage) => byStage[stage])) {
      throw new Error('no seeded scans found in demo data');
    }
    for (const stage of DEMO_STAGES) {
      if (!byStage[stage]) byStage[stage] = toScanResult(FALLBACK_SCAN_RESULT);
    }
    return byStage;
  } catch (err) {
    console.warn(
      '[skinseries] could not read assets/demo/demo_data.json (' +
        (err && err.message ? err.message : 'unknown error') +
        ') — using the embedded fallback result.'
    );
    return {
      baseline: toScanResult(FALLBACK_SCAN_RESULT),
      session3: toScanResult(FALLBACK_SCAN_RESULT),
      session6: toScanResult(FALLBACK_SCAN_RESULT),
    };
  }
}

const demoScans = loadDemoScans();

// ---------------------------------------------------------------------------
// Live task store (in-memory only; a restart clears running task ids)
// ---------------------------------------------------------------------------

const liveTasks = new Map(); // taskId -> { status, result?, errorCode?, createdAt }

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        const err = new Error('payload too large');
        err.statusCode = 413;
        reject(err);
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (size === 0) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (_) {
        const err = new Error('invalid JSON body');
        err.statusCode = 400;
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

// Accepts raw base64 or a data URL; returns a Buffer, or null if unusable.
function decodeBase64Image(input) {
  let data = String(input).trim();
  const dataUrlMatch = data.match(/^data:image\/[a-z0-9.+-]+;base64,(.+)$/i);
  if (dataUrlMatch) data = dataUrlMatch[1];
  if (!data || !/^[A-Za-z0-9+/=\s]+$/.test(data)) return null;
  const buffer = Buffer.from(data.replace(/\s+/g, ''), 'base64');
  return buffer.length > 0 ? buffer : null;
}

function numberOr(...values) {
  for (const value of values) {
    const n = Number(value);
    if (value !== null && value !== undefined && value !== '' && Number.isFinite(n)) return n;
  }
  return null;
}

function stringOr(...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  }
  return null;
}

function youcamHeaders() {
  return { Authorization: 'Bearer ' + API_KEY, 'Content-Type': 'application/json' };
}

async function youcamRequest(url, options, timeoutMs) {
  const res = await fetch(
    url,
    Object.assign({ signal: AbortSignal.timeout(timeoutMs || REQUEST_TIMEOUT_MS) }, options)
  );
  const text = await res.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (_) {
      body = null;
    }
  }
  return { httpStatus: res.status, body };
}

function providerErrorCode(data) {
  const code =
    (data && (data.error_code || data.errorCode)) ||
    (data && data.error && (data.error.code || data.error.error_code)) ||
    (data && data.code) ||
    null;
  return code ? String(code) : 'error_analysis_failed';
}

// ---------------------------------------------------------------------------
// Live YouCam flow (UNTESTED until a real API key exists — see file header)
// ---------------------------------------------------------------------------

// Maps a completed YouCam task payload into the shared ScanResult shape
// (SPEC.md). YouCam returns health scores per concern (`ui_score`, higher =
// healthier, 0–100) plus overall / skin age / skin type items. Field names below
// follow the published docs; lookups are defensive because this path has not
// been exercised against a live key yet.
function mapProviderResult(data) {
  const scores = {};
  let overall = null;
  let skinAge = null;
  let skinType = null;

  const items = Array.isArray(data)
    ? data
    : Array.isArray(data.results)
      ? data.results
      : Array.isArray(data.items)
        ? data.items
        : [];

  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const type = stringOr(item.type, item.name, item.concern) || '';
    const key = type.toLowerCase();
    const score = numberOr(item.ui_score, item.score, item.value);

    if (key === 'all' || key === 'overall') {
      overall = score;
      continue;
    }
    if (key === 'skin_age' || key === 'skinage') {
      skinAge = score;
      continue;
    }
    if (key === 'skin_type' || key === 'skintype') {
      skinType = stringOr(item.value, item.label, item.class, item.score, item.type_value);
      continue;
    }
    const concern = ITEM_TYPE_TO_CONCERN[key];
    if (concern && score !== null) scores[concern] = score;
  }

  if (overall === null && Object.keys(scores).length > 0) {
    const values = Object.values(scores);
    overall = Math.round(values.reduce((sum, n) => sum + n, 0) / values.length);
  }

  if (overall === null && skinAge === null && Object.keys(scores).length === 0) {
    return null; // nothing recognisable in the payload
  }
  return { overall, skinAge, skinType, scores };
}

async function runLivePipeline(taskId, buffer, contentType) {
  const markError = (errorCode) => {
    liveTasks.set(taskId, { status: 'error', errorCode, createdAt: Date.now() });
  };

  // Step 1 — register the file: get a pre-signed upload URL + file id.
  const extension = contentType === 'image/png' ? 'png' : 'jpg';
  const registration = await youcamRequest(
    YOUCAM_BASE + '/s2s/v2.0/file/skin-analysis',
    {
      method: 'POST',
      headers: youcamHeaders(),
      body: JSON.stringify({
        files: [
          {
            content_type: contentType,
            file_name: 'skinseries-' + Date.now() + '.' + extension,
            file_size: buffer.length,
          },
        ],
      }),
    },
    REQUEST_TIMEOUT_MS
  );
  const registeredFile =
    registration.body &&
    registration.body.data &&
    registration.body.data.files &&
    registration.body.data.files[0];
  if (registration.httpStatus !== 200 || !registeredFile) {
    markError('error_upload_failed');
    return;
  }
  const fileId = registeredFile.file_id;
  const uploadRequest = (registeredFile.requests && registeredFile.requests[0]) || {};
  const uploadUrl = uploadRequest.url;
  if (!fileId || !uploadUrl) {
    markError('error_upload_failed');
    return;
  }

  // Step 2 — PUT the image bytes to the pre-signed URL.
  const putResponse = await fetch(uploadUrl, {
    method: 'PUT',
    headers: Object.assign(
      { 'Content-Type': contentType, 'Content-Length': String(buffer.length) },
      uploadRequest.headers || {}
    ),
    body: buffer,
    signal: AbortSignal.timeout(UPLOAD_TIMEOUT_MS),
  });
  if (!putResponse.ok) {
    markError('error_upload_failed');
    return;
  }
  await putResponse.arrayBuffer(); // drain

  // Step 3 — create the analysis task with the SD action list.
  const taskCreation = await youcamRequest(
    YOUCAM_BASE + '/s2s/v2.0/task/skin-analysis',
    {
      method: 'POST',
      headers: youcamHeaders(),
      body: JSON.stringify({ src_file_id: fileId, dst_actions: SD_ACTIONS, format: 'json' }),
    },
    REQUEST_TIMEOUT_MS
  );
  const providerTaskId =
    taskCreation.body && taskCreation.body.data && taskCreation.body.data.task_id;
  if (taskCreation.httpStatus !== 200 || !providerTaskId) {
    markError('error_task_start_failed');
    return;
  }

  // Step 4 — poll until complete, failed, or we time out.
  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
    await sleep(POLL_INTERVAL_MS);
    let poll;
    try {
      poll = await youcamRequest(
        YOUCAM_BASE + '/s2s/v2.0/task/skin-analysis/' + encodeURIComponent(providerTaskId),
        { method: 'GET', headers: youcamHeaders() },
        REQUEST_TIMEOUT_MS
      );
    } catch (_) {
      continue; // transient network hiccup — keep polling
    }
    if (poll.httpStatus === 404) {
      markError('error_task_not_found');
      return;
    }
    const data = (poll.body && poll.body.data) || poll.body;
    if (!data) continue; // empty/undecodable body — keep polling
    const taskStatus = stringOr(data.task_status, data.status) || '';
    const lowered = taskStatus.toLowerCase();

    if (lowered === 'success' || lowered === 'complete' || lowered === 'completed') {
      // Step 5 — map into the shared ScanResult shape.
      const result = mapProviderResult(data);
      if (!result) {
        markError('error_analysis_failed');
        return;
      }
      liveTasks.set(taskId, { status: 'complete', result, createdAt: Date.now() });
      return;
    }
    if (lowered === 'failed' || lowered === 'error' || lowered === 'cancelled') {
      markError(providerErrorCode(data));
      return;
    }
    // Anything else (queued / running / processing) — keep polling.
  }
  markError('error_analysis_timeout');
}

function startLiveScan(buffer, contentType) {
  const taskId = crypto.randomUUID();
  liveTasks.set(taskId, { status: 'running', createdAt: Date.now() });
  runLivePipeline(taskId, buffer, contentType).catch((err) => {
    console.error(
      '[skinseries] live pipeline failed:',
      err && err.message ? err.message : err
    );
    const existing = liveTasks.get(taskId);
    if (existing && existing.status === 'running') {
      liveTasks.set(taskId, {
        status: 'error',
        errorCode: 'error_analysis_failed',
        createdAt: existing.createdAt,
      });
    }
  });
  return taskId;
}

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

async function handlePostScan(req, res) {
  let body;
  try {
    body = await readJsonBody(req);
  } catch (err) {
    if (err && err.statusCode === 413) {
      sendJson(res, 413, { status: 'error', errorCode: 'error_payload_too_large' });
    } else {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message: 'Send a JSON body.',
      });
    }
    return;
  }

  // Simulated errors work in every mode: they mirror the YouCam error surface
  // so the client coaching loop can be developed before a key exists.
  if (body && typeof body.simulateError === 'string') {
    if (!SIMULATED_ERROR_CODES.includes(body.simulateError)) {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message:
          'simulateError must be "error_lighting_dark" or "error_src_face_too_small".',
      });
      return;
    }
    sendJson(res, 422, { status: 'error', errorCode: body.simulateError });
    return;
  }

  // Seeded stages — the demo mode contract.
  if (body && typeof body.demoStage === 'string') {
    if (!DEMO_STAGES.includes(body.demoStage)) {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message: 'demoStage must be "baseline", "session3", or "session6".',
      });
      return;
    }
    if (MODE !== 'demo') {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message:
          'demoStage is served in demo mode only. This server has a YOUCAM_API_KEY set, so it runs in live mode — send { "imageBase64": "..." } instead.',
      });
      return;
    }
    sendJson(res, 200, { status: 'complete', result: demoScans[body.demoStage] });
    return;
  }

  // Photo upload — the real YouCam flow, live mode only.
  if (body && typeof body.imageBase64 === 'string' && body.imageBase64.trim()) {
    if (MODE !== 'live') {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message:
          'Photo uploads run in live mode only; this server has no YOUCAM_API_KEY set, so it is serving seeded demo results. Send { "demoStage": "baseline" } (or "session3" / "session6") instead.',
      });
      return;
    }
    const buffer = decodeBase64Image(body.imageBase64);
    if (!buffer) {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_bad_request',
        message: 'imageBase64 must be valid base64-encoded JPEG or PNG data.',
      });
      return;
    }
    const contentType = body.contentType === 'image/png' ? 'image/png' : 'image/jpeg';
    const taskId = startLiveScan(buffer, contentType);
    sendJson(res, 200, { taskId, status: 'running' });
    return;
  }

  sendJson(res, 400, {
    status: 'error',
    errorCode: 'error_bad_request',
    message:
      'Send { "demoStage": ... } for seeded results, { "simulateError": ... } to rehearse coaching, or { "imageBase64": ... } in live mode.',
  });
}

function handleGetScan(taskId, res) {
  const record = liveTasks.get(taskId);
  if (!record) {
    sendJson(res, 404, {
      status: 'error',
      errorCode: 'error_task_not_found',
      message:
        MODE === 'demo'
          ? 'Task ids exist only in live mode. In demo mode, POST /api/scans with { "demoStage": "baseline" } (or "session3" / "session6") to get a result.'
          : 'Unknown taskId. Task ids are held in memory and clear if the server restarts.',
    });
    return;
  }
  if (record.status === 'complete') {
    sendJson(res, 200, { status: 'complete', result: record.result });
  } else if (record.status === 'error') {
    sendJson(res, 200, { status: 'error', errorCode: record.errorCode });
  } else {
    sendJson(res, 200, { status: 'running' });
  }
}

const server = http.createServer(async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  let pathname;
  try {
    pathname = new URL(req.url, 'http://localhost').pathname.replace(/\/+$/, '') || '/';
  } catch (_) {
    sendJson(res, 400, { status: 'error', errorCode: 'error_bad_request' });
    return;
  }

  if (req.method === 'GET' && pathname === '/health') {
    sendJson(res, 200, { ok: true, mode: MODE });
    return;
  }

  if (pathname === '/api/scans') {
    if (req.method === 'POST') {
      try {
        await handlePostScan(req, res);
      } catch (err) {
        console.error('[skinseries] request failed:', err && err.message ? err.message : err);
        if (!res.headersSent) {
          sendJson(res, 500, { status: 'error', errorCode: 'error_internal' });
        }
      }
      return;
    }
    sendJson(res, 405, { status: 'error', errorCode: 'error_method_not_allowed' });
    return;
  }

  const scanMatch = pathname.match(/^\/api\/scans\/([^/]+)$/);
  if (scanMatch) {
    if (req.method === 'GET') {
      handleGetScan(decodeURIComponent(scanMatch[1]), res);
      return;
    }
    sendJson(res, 405, { status: 'error', errorCode: 'error_method_not_allowed' });
    return;
  }

  sendJson(res, 404, { status: 'error', errorCode: 'error_not_found' });
});

server.listen(PORT, () => {
  console.log(
    '[skinseries] backend proxy listening on http://localhost:' + PORT + ' (' + MODE + ' mode)'
  );
  if (MODE === 'demo') {
    console.log(
      '[skinseries] demo mode — serving seeded results from assets/demo/demo_data.json; no network calls.'
    );
  } else {
    console.log(
      '[skinseries] live mode — YOUCAM_API_KEY is set. The YouCam flow is written to the docs but UNTESTED until the key is verified.'
    );
  }
});
