'use strict';

// EstiSeries backend — the only component that holds the YouCam API key.
// Zero-dependency Node.js (>= 18): built-in `http` plus the global `fetch`.
//
// Production shape (API contract v2, docs/api-contract-v2.md):
//   Practitioners (estheticians) own clients. Every API read/write is scoped
//   by a token: practitioner endpoints need `Authorization: Bearer <token>`;
//   client endpoints are keyed by the client token in the path (the token is
//   the credential inside the client's personal link, /?c=<token>).
//   State lives in a JSON file store (data.json, atomic writes) — small,
//   single-server, zero dependencies.
//   Scans run the real YouCam (Perfect Corp YCE) async flow against
//   https://yce-api-01.makeupar.com:
//     1. POST /s2s/v2.0/file/skin-analysis   -> pre-signed upload URL + file id
//     2. PUT the image bytes to that URL
//     3. POST /s2s/v2.0/task/skin-analysis   -> task_id (SD action list)
//     4. GET  /s2s/v2.0/task/skin-analysis/<task_id> until complete
//     5. Map the response into the shared ScanResult shape and append it to
//        the scanning client's series record.
//   The live flow + result mapper were verified end-to-end against the real
//   API on 2026-10-19 (payload anatomy documented at mapProviderResult; a
//   captured sample is raw-sample.json, gitignored).
//
// Seeded data survives in exactly one place: the judge demo accounts
// (demo practitioner + her demo client, seeded from seed-demo.json at store
// init). Nothing else serves seeded results; there is no demo mode.

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const YOUCAM_BASE = 'https://yce-api-01.makeupar.com';
const DATA_PATH = process.env.DATA_PATH || path.join(__dirname, 'data.json');
const SEED_PATH = path.join(__dirname, 'seed-demo.json');
// Error codes the client coaching loop develops against; mirrors the YouCam
// error surface so the same client code works for real and rehearsed errors.
const SIMULATED_ERROR_CODES = ['error_lighting_dark', 'error_src_face_too_small'];
const MAX_BODY_BYTES = 25 * 1024 * 1024; // base64 photos are large
const REQUEST_TIMEOUT_MS = 30000;
const UPLOAD_TIMEOUT_MS = 60000;
const POLL_INTERVAL_MS = 2000;
const MAX_POLL_ATTEMPTS = 150; // ~5 minutes upstream, then report an error

// Demo judge accounts (docs/api-contract-v2.md). The demo client's token is
// fixed and shareable on purpose — it only ever exposes fictional data.
const DEMO_LOGIN = 'demo@estiseries.app';
const DEMO_PASSWORD = 'GlowDemo2026';
const DEMO_CLIENT_TOKEN = 'demo-maya-r';
const SAMPLE_PRACTICE_NAME = 'EstiSeries Sample Studio';

// Practice logos (v2.1): the uploaded bytes live on disk under
// backend/logos/ — the JSON store only keeps {ext, updatedAt}. Only these
// raster types are accepted.
const LOGOS_DIR = path.join(__dirname, 'logos');
const LOGO_EXT_BY_CONTENT_TYPE = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
};
const LOGO_CONTENT_TYPE_BY_EXT = {
  png: 'image/png',
  jpg: 'image/jpeg',
  webp: 'image/webp',
};
const MAX_LOGO_BYTES = 2 * 1024 * 1024;

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
    // No .env file is fine for store-only endpoints — scans need the key.
  }
}

loadDotEnv();

// Mail (v2.2): verification + recovery email. The mailer reads its own
// configuration (SMTP_*, MAIL_FROM, MAIL_TRANSPORT) from the environment —
// which now includes backend/.env — and never logs a credential.
const { sendMail, TRANSPORT: MAIL_TRANSPORT } = require('./mailer');

const PUBLIC_BASE_URL = (
  process.env.PUBLIC_BASE_URL || 'https://estiseries.ignisalgos.com'
).replace(/\/+$/, '');
const VERIFY_TOKEN_TTL_MS = 24 * 60 * 60 * 1000; // verification links: 24h
const RESET_TOKEN_TTL_MS = 60 * 60 * 1000; // password-reset links: 1h

const API_KEY =
  process.env.YOUCAM_API_KEY && process.env.YOUCAM_API_KEY.trim()
    ? process.env.YOUCAM_API_KEY.trim()
    : null;
const MODE = API_KEY ? 'live' : 'unconfigured';
const PORT = Number.parseInt(process.env.PORT || '', 10) || 8787;

// ---------------------------------------------------------------------------
// Store (JSON file, atomic writes)
// ---------------------------------------------------------------------------

function newToken() {
  return crypto.randomBytes(24).toString('base64url');
}

function hashPassword(salt, password) {
  return crypto.createHash('sha256').update(salt + ':' + password).digest('hex');
}

// --- Accounts (v2.2): scrypt passwords + one-time email tokens ------------
// Passwords are stored as one combined scrypt string:
// "scrypt$<salt base64>$<hash base64>" with a per-password random salt.
// One-time tokens (verify / reset) are 32 random bytes hex-encoded; only
// their sha256 hash is ever stored, and each is single-use.

function hashPasswordScrypt(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 64);
  return 'scrypt$' + salt.toString('base64') + '$' + hash.toString('base64');
}

function verifyPasswordScrypt(password, stored) {
  try {
    const parts = String(stored || '').split('$');
    if (parts.length !== 3 || parts[0] !== 'scrypt') return false;
    const salt = Buffer.from(parts[1], 'base64');
    const expected = Buffer.from(parts[2], 'base64');
    if (!salt.length || !expected.length) return false;
    const actual = crypto.scryptSync(password, salt, expected.length);
    return crypto.timingSafeEqual(actual, expected);
  } catch (_) {
    return false;
  }
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function mintOneTimeToken(holder, kind) {
  const raw = crypto.randomBytes(32).toString('hex');
  const ttl = kind === 'verify' ? VERIFY_TOKEN_TTL_MS : RESET_TOKEN_TTL_MS;
  holder[kind + 'TokenHash'] = sha256Hex(raw);
  holder[kind + 'ExpiresAt'] = new Date(Date.now() + ttl).toISOString();
  return raw;
}

function isValidEmail(email) {
  return (
    typeof email === 'string' &&
    email.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  );
}

// Practitioners are found by their account email; the legacy demo-style
// `login.login` still matches so old records keep signing in.
function findPractitionerByEmail(email) {
  if (!email) return null;
  const target = String(email).trim().toLowerCase();
  if (!target) return null;
  return (
    store.practitioners.find(
      (p) =>
        (p.email && p.email === target) ||
        (p.login && p.login.login && p.login.login.toLowerCase() === target)
    ) || null
  );
}

function findClientAccountByEmail(email) {
  if (!email) return null;
  const target = String(email).trim().toLowerCase();
  if (!target) return null;
  for (const practitioner of store.practitioners) {
    for (const client of practitioner.clients) {
      if (client.account && client.account.email === target) {
        return { practitioner, client };
      }
    }
  }
  return null;
}

// Finds the holder (practitioner record or client.account) of a one-time
// token by its hash, across both stores. Expired tokens do not match.
function findOneTimeToken(kind, rawToken) {
  if (!rawToken || typeof rawToken !== 'string') return null;
  const hash = sha256Hex(rawToken.trim());
  const hashKey = kind + 'TokenHash';
  const expKey = kind + 'ExpiresAt';
  const matches = (holder) =>
    holder &&
    holder[hashKey] &&
    holder[hashKey] === hash &&
    holder[expKey] &&
    Date.parse(holder[expKey]) > Date.now();
  for (const p of store.practitioners) {
    if (matches(p)) return { role: 'practitioner', holder: p, practitioner: p };
  }
  for (const p of store.practitioners) {
    for (const c of p.clients) {
      if (c.account && matches(c.account)) {
        return { role: 'client', holder: c.account, practitioner: p, client: c };
      }
    }
  }
  return null;
}

function verifyPractitionerPassword(practitioner, password) {
  if (practitioner.passwordHash) {
    return verifyPasswordScrypt(password, practitioner.passwordHash);
  }
  if (practitioner.login && practitioner.login.salt && practitioner.login.hash) {
    const candidate = Buffer.from(
      hashPassword(practitioner.login.salt, password),
      'utf8'
    );
    const expected = Buffer.from(practitioner.login.hash, 'utf8');
    return (
      candidate.length === expected.length &&
      crypto.timingSafeEqual(candidate, expected)
    );
  }
  return false;
}

async function sendVerificationEmail(email, rawToken) {
  const link = PUBLIC_BASE_URL + '/verify?token=' + rawToken;
  const result = await sendMail({
    to: email,
    subject: 'Verify your EstiSeries email',
    text:
      'Hello,\n\n' +
      'Confirm this email address for your EstiSeries account so you can ' +
      'recover access if you ever lose your phone or get signed out:\n\n' +
      link +
      '\n\nThis link expires in 24 hours. If you did not create an ' +
      'EstiSeries account, you can ignore this email.\n\n— EstiSeries',
  });
  if (!result.ok) {
    console.error(
      '[estiseries] verification email failed (' +
        result.transport +
        '): ' +
        (result.error || 'unknown error')
    );
  }
}

async function sendResetEmail(email, rawToken) {
  const link = PUBLIC_BASE_URL + '/reset?token=' + rawToken;
  const result = await sendMail({
    to: email,
    subject: 'Reset your EstiSeries password',
    text:
      'Hello,\n\n' +
      'We received a request to reset the password for your EstiSeries ' +
      'account. Choose a new password here:\n\n' +
      link +
      '\n\nThis link expires in 1 hour. If you did not request a reset, ' +
      'you can ignore this email — your password will not change.' +
      '\n\n— EstiSeries',
  });
  if (!result.ok) {
    console.error(
      '[estiseries] reset email failed (' +
        result.transport +
        '): ' +
        (result.error || 'unknown error')
    );
  }
}

function loadStore() {
  try {
    const parsed = JSON.parse(fs.readFileSync(DATA_PATH, 'utf8'));
    if (parsed && Array.isArray(parsed.practitioners)) return parsed;
  } catch (_) {
    // Missing/corrupt store — start fresh; seed data is re-created below.
  }
  return { practitioners: [] };
}

const store = loadStore();

function saveStore() {
  const tmp = DATA_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2));
  fs.renameSync(tmp, DATA_PATH);
}

function findPractitionerByToken(token) {
  if (!token) return null;
  return store.practitioners.find((p) => p.token === token) || null;
}

function findClientByToken(token) {
  if (!token) return null;
  for (const practitioner of store.practitioners) {
    const client = practitioner.clients.find((c) => c.token === token);
    if (client) return { practitioner, client };
  }
  return null;
}

function publicPractitioner(p) {
  return {
    id: p.id,
    practiceName: p.practiceName,
    practitionerName: p.practitionerName,
    accent: p.accent,
    bookingLink: p.bookingLink,
    createdAt: p.createdAt,
    clientCount: p.clients.length,
    logoUrl: p.logo ? '/api/practitioners/' + p.id + '/logo' : null,
    offerings: p.offerings || [],
    email: p.email || null,
    emailVerified: !!p.emailVerified,
  };
}

function clientSummary(c) {
  const latest = c.scans.length ? c.scans[c.scans.length - 1] : null;
  return {
    id: c.id,
    firstName: c.firstName,
    createdAt: c.createdAt,
    token: c.token,
    link: '/?c=' + c.token,
    scanCount: c.scans.length,
    latestOverall: latest ? latest.result.overall : null,
    latestScanAt: latest ? latest.timestamp : null,
    plan: c.plan || null,
  };
}

function clientFull(c) {
  return Object.assign(clientSummary(c), {
    scans: c.scans.map((s) => ({
      taskId: s.taskId,
      label: s.label,
      timestamp: s.timestamp,
      result: s.result,
    })),
  });
}

// ---------------------------------------------------------------------------
// Seeding — built-in sample practitioner (backs the public try-it path) and
// the judge demo accounts. Runs at store init when absent; idempotent.
// ---------------------------------------------------------------------------

function seedStore() {
  let changed = false;

  if (!store.practitioners.some((p) => p.sample)) {
    store.practitioners.push({
      id: 'sample',
      token: newToken(),
      practiceName: SAMPLE_PRACTICE_NAME,
      practitionerName: 'EstiSeries',
      accent: '#7D8C74',
      bookingLink: '',
      createdAt: new Date().toISOString(),
      sample: true,
      demo: false,
      login: null,
      clients: [],
    });
    changed = true;
  }

  if (!store.practitioners.some((p) => p.demo)) {
    try {
      const seed = JSON.parse(fs.readFileSync(SEED_PATH, 'utf8'));
      const salt = crypto.randomBytes(8).toString('hex');
      const demoClient = {
        id: crypto.randomUUID(),
        token: DEMO_CLIENT_TOKEN,
        firstName: seed.client.firstName,
        createdAt: new Date().toISOString(),
        oneOff: false,
        plan: seed.client.plan,
        scans: seed.client.scans,
      };
      store.practitioners.push({
        id: crypto.randomUUID(),
        token: newToken(),
        practiceName: seed.practice.practiceName,
        practitionerName: seed.practice.practitionerName,
        accent: seed.practice.accent,
        bookingLink: seed.practice.bookingLink,
        createdAt: new Date().toISOString(),
        sample: false,
        demo: true,
        login: {
          login: DEMO_LOGIN,
          salt,
          hash: hashPassword(salt, DEMO_PASSWORD),
        },
        email: DEMO_LOGIN,
        passwordHash: hashPasswordScrypt(DEMO_PASSWORD),
        emailVerified: true,
        verifyTokenHash: null,
        verifyExpiresAt: null,
        resetTokenHash: null,
        resetExpiresAt: null,
        clients: [demoClient],
      });
      changed = true;
    } catch (err) {
      console.warn(
        '[estiseries] could not seed demo accounts (' +
          (err && err.message ? err.message : 'unknown error') +
          ') — continuing without them.'
      );
    }
  }

  if (changed) saveStore();
}

seedStore();

// ---------------------------------------------------------------------------
// Migration (v2.1) — practitioner records gain `offerings` and `logo`.
// Runs after seeding so freshly seeded records are covered too. The demo
// practitioner, if she has no offerings field at all, is seeded with a
// small menu so the judge accounts show the feature working; no other
// practitioner's data changes.
// ---------------------------------------------------------------------------

function migrateStore() {
  let changed = false;
  const now = new Date().toISOString();
  const seedOffering = (fields) =>
    Object.assign({ id: crypto.randomUUID(), active: true, createdAt: now }, fields);

  for (const p of store.practitioners) {
    if (p.demo && p.login && p.login.login === DEMO_LOGIN && p.offerings === undefined) {
      p.offerings = [
        seedOffering({ kind: 'service', name: 'Botox® Cosmetic', price: 12, unit: 'per unit' }),
        seedOffering({
          kind: 'service',
          name: 'RF Microneedling',
          price: 350,
          unit: 'per session',
          durationMin: 60,
        }),
        seedOffering({ kind: 'service', name: 'Signature Glow Facial', price: 120, durationMin: 60 }),
        seedOffering({ kind: 'product', name: 'Gentle Renewal Cleanser', price: 38 }),
        seedOffering({ kind: 'product', name: 'Hydration Boost Serum', price: 64 }),
      ];
      changed = true;
    }
    if (!Array.isArray(p.offerings)) {
      p.offerings = [];
      changed = true;
    }
    if (!('logo' in p)) {
      p.logo = null;
      changed = true;
    }
    // Accounts (v2.2): every practitioner record gains the account fields
    // (nulls until she adds an email + password); every client record
    // gains `account` (null until the client creates a login). The demo
    // practitioner is normalized to a verified account for the seeded
    // demo password.
    for (const field of [
      'email',
      'passwordHash',
      'verifyTokenHash',
      'verifyExpiresAt',
      'resetTokenHash',
      'resetExpiresAt',
    ]) {
      if (!(field in p)) {
        p[field] = null;
        changed = true;
      }
    }
    if (!('emailVerified' in p)) {
      p.emailVerified = false;
      changed = true;
    }
    if (p.demo && p.login && p.login.login === DEMO_LOGIN) {
      if (p.email !== DEMO_LOGIN) {
        p.email = DEMO_LOGIN;
        changed = true;
      }
      if (!p.passwordHash) {
        p.passwordHash = hashPasswordScrypt(DEMO_PASSWORD);
        changed = true;
      }
      if (p.emailVerified !== true) {
        p.emailVerified = true;
        changed = true;
      }
    }
    for (const c of p.clients) {
      if (!('account' in c)) {
        c.account = null;
        changed = true;
      }
    }
  }

  if (changed) saveStore();
}

migrateStore();

// ---------------------------------------------------------------------------
// Live task store (in-memory only; a restart clears running task ids —
// completed results are already persisted into the client's series record)
// ---------------------------------------------------------------------------

const liveTasks = new Map(); // taskId -> { status, result?, errorCode?, clientToken, createdAt, appended }

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
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
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

function requireString(body, field) {
  const value = body && typeof body[field] === 'string' ? body[field].trim() : '';
  return value || null;
}

// ---------------------------------------------------------------------------
// Live YouCam flow (verified end-to-end 2026-10-19 — see file header)
// ---------------------------------------------------------------------------

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
    // Real failure payloads (verified 2026-10-19) carry the code as a plain
    // string in `error`, e.g. "error_src_face_too_small". The client coaching
    // loop keys off these codes, so they must survive mapping instead of
    // collapsing into error_analysis_failed.
    (data && typeof data.error === 'string' && data.error ? data.error : null) ||
    (data && data.code) ||
    null;
  return code ? String(code) : 'error_analysis_failed';
}

// Maps a completed YouCam task payload into the shared ScanResult shape
// (SPEC.md). YouCam returns health scores per concern (`ui_score`, higher =
// healthier, 0–100) plus overall / skin age / skin type items. The item layout
// below is the real one, captured from a live task on 2026-10-19 (see
// raw-sample.json): `data.results` is an envelope whose `output` array holds
// one item per action - concern items carry `ui_score`, the `all` item
// carries the overall as a float `score`, `skin_age` carries `score`, and
// `skin_type` arrives as one item per region (whole / t_zone / u_zone) with
// the classification in its `skin_type` field.
function mapProviderResult(data) {
  const scores = {};
  const masks = {};
  let overall = null;
  let skinAge = null;
  let skinType = null;

  // Real payload: `results` is an envelope object, NOT the item array -
  // the items live at `results.output`. The flatter shapes are fallbacks.
  const items = Array.isArray(data)
    ? data
    : data.results && Array.isArray(data.results.output)
      ? data.results.output
      : Array.isArray(data.results)
        ? data.results
        : Array.isArray(data.items)
          ? data.items
          : Array.isArray(data.output)
            ? data.output
            : [];

  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const type = stringOr(item.type, item.name, item.concern) || '';
    const key = type.toLowerCase();
    const score = numberOr(item.ui_score, item.score, item.value);

    if (key === 'all' || key === 'overall') {
      // The `all` item carries a float score (e.g. 74.73); ScanResult's
      // overall is an integer everywhere else.
      overall = score === null ? null : Math.round(score);
      continue;
    }
    if (key === 'skin_age' || key === 'skinage') {
      skinAge = score;
      continue;
    }
    if (key === 'skin_type' || key === 'skintype') {
      // Real payload: one item per region with the classification in
      // `skin_type`. The whole-face region wins; other regions only fill in
      // while it is missing.
      const classified = stringOr(
        item.skin_type,
        item.value,
        item.label,
        item.class,
        item.type_value
      );
      if (classified && (item.region === 'whole' || skinType === null)) {
        skinType = classified;
      }
      continue;
    }
    const concern = ITEM_TYPE_TO_CONCERN[key];
    if (concern && score !== null) scores[concern] = score;
    if (concern && Array.isArray(item.mask_urls) && item.mask_urls[0]) {
      // Provider-generated region mask for this concern (a signed URL that
      // expires ~2h after the task). Additive + optional: consumers use it
      // only to enhance a fresh report, never as the stored source of truth.
      if (!masks[concern]) masks[concern] = item.mask_urls[0];
    }
  }

  if (overall === null && Object.keys(scores).length > 0) {
    const values = Object.values(scores);
    overall = Math.round(values.reduce((sum, n) => sum + n, 0) / values.length);
  }

  if (overall === null && skinAge === null && Object.keys(scores).length === 0) {
    return null; // nothing recognisable in the payload
  }
  return Object.assign({ overall, skinAge, skinType, scores }, Object.keys(masks).length ? { masks } : {});
}

// Persists a completed result into the owning client's series — exactly once
// per task. Called by the pipeline on completion.
function appendScanToClient(taskId, result) {
  const task = liveTasks.get(taskId);
  if (!task || task.appended || !task.clientToken) return;
  const found = findClientByToken(task.clientToken);
  if (!found) return;
  const { client } = found;
  const label = client.scans.length === 0 ? 'Baseline' : 'Scan ' + (client.scans.length + 1);
  client.scans.push({
    taskId,
    label,
    timestamp: new Date().toISOString(),
    result,
  });
  task.appended = true;
  saveStore();
}

async function runLivePipeline(taskId, buffer, contentType) {
  const markError = (errorCode) => {
    const existing = liveTasks.get(taskId) || {};
    liveTasks.set(
      taskId,
      Object.assign({}, existing, { status: 'error', errorCode, createdAt: Date.now() })
    );
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
            file_name: 'estiseries-' + Date.now() + '.' + extension,
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
      // Step 5 — map into the shared ScanResult shape and persist it into
      // the scanning client's series record.
      const result = mapProviderResult(data);
      if (!result) {
        markError('error_analysis_failed');
        return;
      }
      const existing = liveTasks.get(taskId) || {};
      liveTasks.set(
        taskId,
        Object.assign({}, existing, { status: 'complete', result, createdAt: Date.now() })
      );
      appendScanToClient(taskId, result);
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

function startLiveScan(clientToken, buffer, contentType) {
  const taskId = crypto.randomUUID();
  liveTasks.set(taskId, {
    status: 'running',
    clientToken,
    createdAt: Date.now(),
    appended: false,
  });
  runLivePipeline(taskId, buffer, contentType).catch((err) => {
    console.error('[estiseries] live pipeline failed:', err && err.message ? err.message : err);
    const existing = liveTasks.get(taskId);
    if (existing && existing.status === 'running') {
      liveTasks.set(
        taskId,
        Object.assign({}, existing, { status: 'error', errorCode: 'error_analysis_failed' })
      );
    }
  });
  return taskId;
}

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

async function parseBody(req, res) {
  try {
    return await readJsonBody(req);
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
    return null;
  }
}

function badRequest(res, message) {
  sendJson(res, 400, { status: 'error', errorCode: 'error_bad_request', message });
}

function notFound(res, errorCode, message) {
  sendJson(res, 404, { status: 'error', errorCode, message });
}

function unauthorized(res) {
  sendJson(res, 401, {
    status: 'error',
    errorCode: 'error_unauthorized',
    message: 'A valid practitioner token is required.',
  });
}

function authPractitioner(req) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? findPractitionerByToken(match[1].trim()) : null;
}

function editableProfile(body, target) {
  for (const field of ['practiceName', 'practitionerName', 'accent', 'bookingLink']) {
    if (typeof body[field] === 'string') target[field] = body[field].trim();
  }
}

async function handleCreatePractitioner(body, res) {
  const practiceName = requireString(body, 'practiceName');
  const practitionerName = requireString(body, 'practitionerName');
  if (!practiceName || !practitionerName) {
    badRequest(res, 'practiceName and practitionerName are required.');
    return;
  }
  // Optional email + password (v2.2): makes the account recoverable.
  // Calls without an email keep the legacy token-only behavior exactly.
  let email = null;
  let passwordHash = null;
  if (typeof body.email === 'string' && body.email.trim()) {
    email = body.email.trim().toLowerCase();
    if (!isValidEmail(email)) {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_invalid_email',
        message: 'That email address does not look right.',
      });
      return;
    }
    const password = typeof body.password === 'string' ? body.password : '';
    if (password.length < 8) {
      sendJson(res, 400, {
        status: 'error',
        errorCode: 'error_invalid_password',
        message: 'Choose a password of at least 8 characters.',
      });
      return;
    }
    if (findPractitionerByEmail(email)) {
      sendJson(res, 409, {
        status: 'error',
        errorCode: 'error_email_taken',
        message: 'An account with that email already exists — sign in instead.',
      });
      return;
    }
    passwordHash = hashPasswordScrypt(password);
  }
  const practitioner = {
    id: crypto.randomUUID(),
    token: newToken(),
    practiceName,
    practitionerName,
    accent: typeof body.accent === 'string' && body.accent.trim() ? body.accent.trim() : '#B0714F',
    bookingLink:
      typeof body.bookingLink === 'string' ? body.bookingLink.trim() : '',
    createdAt: new Date().toISOString(),
    sample: false,
    demo: false,
    login: null,
    email,
    passwordHash,
    emailVerified: false,
    verifyTokenHash: null,
    verifyExpiresAt: null,
    resetTokenHash: null,
    resetExpiresAt: null,
    offerings: [],
    logo: null,
    clients: [],
  };
  store.practitioners.push(practitioner);
  let verifyRaw = null;
  if (email) verifyRaw = mintOneTimeToken(practitioner, 'verify');
  saveStore();
  if (email) await sendVerificationEmail(email, verifyRaw);
  sendJson(
    res,
    201,
    Object.assign({ token: practitioner.token }, publicPractitioner(practitioner))
  );
}

function handleLogin(body, res) {
  const login = requireString(body, 'login');
  const password = typeof body.password === 'string' ? body.password : '';
  const practitioner = login ? findPractitionerByEmail(login) : null;
  if (!practitioner || !verifyPractitionerPassword(practitioner, password)) {
    unauthorized(res);
    return;
  }
  sendJson(res, 200, {
    token: practitioner.token,
    practitioner: publicPractitioner(practitioner),
  });
}

// --- Accounts (v2.2): verification, recovery, client logins ---------------

function invalidEmail(res) {
  sendJson(res, 400, {
    status: 'error',
    errorCode: 'error_invalid_email',
    message: 'That email address does not look right.',
  });
}

function invalidPassword(res) {
  sendJson(res, 400, {
    status: 'error',
    errorCode: 'error_invalid_password',
    message: 'Choose a password of at least 8 characters.',
  });
}

function emailTaken(res) {
  sendJson(res, 409, {
    status: 'error',
    errorCode: 'error_email_taken',
    message: 'An account with that email already exists — sign in instead.',
  });
}

function tokenInvalid(res) {
  sendJson(res, 400, {
    status: 'error',
    errorCode: 'error_token_invalid',
    message: 'That link is invalid or has expired. Request a fresh one and try again.',
  });
}

// POST /api/me/account (Bearer): a token-only practitioner adds (or
// changes) her email + password. The new email starts unverified.
async function handleSetAccount(practitioner, body, res) {
  const email =
    body && typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (!isValidEmail(email)) {
    invalidEmail(res);
    return;
  }
  const password = body && typeof body.password === 'string' ? body.password : '';
  if (password.length < 8) {
    invalidPassword(res);
    return;
  }
  const existing = findPractitionerByEmail(email);
  if (existing && existing.id !== practitioner.id) {
    emailTaken(res);
    return;
  }
  practitioner.email = email;
  practitioner.passwordHash = hashPasswordScrypt(password);
  practitioner.emailVerified = false;
  const raw = mintOneTimeToken(practitioner, 'verify');
  saveStore();
  await sendVerificationEmail(email, raw);
  sendJson(res, 200, publicPractitioner(practitioner));
}

// POST /api/auth/verify-email {token} — one token space for practitioners
// and clients; the response says which role it belonged to.
function handleVerifyEmail(body, res) {
  const found = findOneTimeToken('verify', body && body.token);
  if (!found) {
    tokenInvalid(res);
    return;
  }
  found.holder.emailVerified = true;
  found.holder.verifyTokenHash = null;
  found.holder.verifyExpiresAt = null;
  saveStore();
  sendJson(res, 200, { ok: true, role: found.role });
}

// POST /api/auth/resend-verification {email} — always {ok:true} so the
// endpoint never reveals whether an account exists.
async function handleResendVerification(body, res) {
  const email =
    body && typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email) {
    const practitioner = findPractitionerByEmail(email);
    if (practitioner && practitioner.email && !practitioner.emailVerified) {
      const raw = mintOneTimeToken(practitioner, 'verify');
      saveStore();
      await sendVerificationEmail(practitioner.email, raw);
    } else {
      const foundClient = findClientAccountByEmail(email);
      if (foundClient && !foundClient.client.account.emailVerified) {
        const raw = mintOneTimeToken(foundClient.client.account, 'verify');
        saveStore();
        await sendVerificationEmail(email, raw);
      }
    }
  }
  sendJson(res, 200, { ok: true });
}

// POST /api/auth/forgot-password {email} — always {ok:true}; a reset link
// is emailed only when an account actually owns the address.
async function handleForgotPassword(body, res) {
  const email =
    body && typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email) {
    const practitioner = findPractitionerByEmail(email);
    if (practitioner && (practitioner.passwordHash || practitioner.login)) {
      const raw = mintOneTimeToken(practitioner, 'reset');
      saveStore();
      await sendResetEmail(practitioner.email || email, raw);
    } else {
      const foundClient = findClientAccountByEmail(email);
      if (foundClient && foundClient.client.account.passwordHash) {
        const raw = mintOneTimeToken(foundClient.client.account, 'reset');
        saveStore();
        await sendResetEmail(email, raw);
      }
    }
  }
  sendJson(res, 200, { ok: true });
}

// POST /api/auth/reset-password {token, newPassword} — the emailed token
// proves mailbox ownership, so a successful reset also verifies the email.
function handleResetPassword(body, res) {
  const newPassword =
    body && typeof body.newPassword === 'string' ? body.newPassword : '';
  if (newPassword.length < 8) {
    invalidPassword(res);
    return;
  }
  const found = findOneTimeToken('reset', body && body.token);
  if (!found) {
    tokenInvalid(res);
    return;
  }
  found.holder.passwordHash = hashPasswordScrypt(newPassword);
  found.holder.emailVerified = true;
  found.holder.resetTokenHash = null;
  found.holder.resetExpiresAt = null;
  found.holder.verifyTokenHash = null;
  found.holder.verifyExpiresAt = null;
  saveStore();
  sendJson(res, 200, { ok: true, role: found.role });
}

// POST /api/clients/:token/account {email, password} — OPTIONAL client
// login, bound to the client record the link token names. The link alone
// keeps working exactly as before; this exists only so the client can
// sign back in on a new device without the link.
async function handleCreateClientAccount(token, body, res) {
  const found = findClientByToken(token);
  if (!found) {
    notFound(res, 'error_client_not_found', 'This link is not active.');
    return;
  }
  const email =
    body && typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (!isValidEmail(email)) {
    invalidEmail(res);
    return;
  }
  const password = body && typeof body.password === 'string' ? body.password : '';
  if (password.length < 8) {
    invalidPassword(res);
    return;
  }
  const clash = findClientAccountByEmail(email);
  if (clash && clash.client.id !== found.client.id) {
    emailTaken(res);
    return;
  }
  const account = {
    email,
    passwordHash: hashPasswordScrypt(password),
    emailVerified: false,
    verifyTokenHash: null,
    verifyExpiresAt: null,
    resetTokenHash: null,
    resetExpiresAt: null,
  };
  found.client.account = account;
  const raw = mintOneTimeToken(account, 'verify');
  saveStore();
  await sendVerificationEmail(email, raw);
  sendJson(res, 200, { ok: true, email, emailVerified: false });
}

// POST /api/clients/signin {email, password} — the lost-phone path: no
// personal link needed. Returns the client's own token plus the same
// public practitioner shape the client view renders.
function handleClientSignin(body, res) {
  const email =
    body && typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = body && typeof body.password === 'string' ? body.password : '';
  const found = email ? findClientAccountByEmail(email) : null;
  if (
    !found ||
    !verifyPasswordScrypt(password, found.client.account.passwordHash)
  ) {
    unauthorized(res);
    return;
  }
  const { practitioner, client } = found;
  sendJson(res, 200, {
    clientToken: client.token,
    practitioner: {
      practiceName: practitioner.practiceName,
      practitionerName: practitioner.practitionerName,
      accent: practitioner.accent,
      bookingLink: practitioner.bookingLink,
      logoUrl: practitioner.logo
        ? '/api/practitioners/' + practitioner.id + '/logo'
        : null,
      offerings: (practitioner.offerings || []).filter((o) => o.active),
    },
    client: { firstName: client.firstName },
  });
}

function handleCreateClient(practitioner, body, res) {
  const firstName = requireString(body, 'firstName');
  if (!firstName) {
    badRequest(res, 'firstName is required.');
    return;
  }
  if (body.plan !== undefined && (typeof body.plan !== 'object' || body.plan === null)) {
    badRequest(res, 'plan must be a JSON object when provided.');
    return;
  }
  const client = {
    id: crypto.randomUUID(),
    token: newToken(),
    firstName,
    createdAt: new Date().toISOString(),
    oneOff: false,
    plan: body.plan || null,
    scans: [],
  };
  practitioner.clients.push(client);
  saveStore();
  sendJson(res, 201, clientFull(client));
}

function ownClientOr404(practitioner, clientId, res) {
  const client = practitioner.clients.find((c) => c.id === clientId);
  if (!client) {
    notFound(res, 'error_client_not_found', 'No such client for this practitioner.');
    return null;
  }
  return client;
}

// --- Offerings (v2.1): the practitioner's own services & products --------

// Validates an offering body; returns the editable fields, or null when
// the body is not a usable offering (the routes answer
// error_invalid_offering).
function validateOffering(body) {
  if (!body || typeof body !== 'object') return null;
  if (body.kind !== 'service' && body.kind !== 'product') return null;
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (!name || name.length > 120) return null;
  if (typeof body.price !== 'number' || !Number.isFinite(body.price)) return null;
  if (body.price < 0 || body.price > 100000) return null;
  const fields = { kind: body.kind, name, price: body.price };
  if (typeof body.unit === 'string' && body.unit.trim()) fields.unit = body.unit.trim();
  if (body.durationMin !== undefined && body.durationMin !== null) {
    if (
      !Number.isInteger(body.durationMin) ||
      body.durationMin < 0 ||
      body.durationMin > 1440
    ) {
      return null;
    }
    fields.durationMin = body.durationMin;
  }
  if (typeof body.description === 'string' && body.description.trim()) {
    fields.description = body.description.trim();
  }
  return fields;
}

function invalidOffering(res) {
  sendJson(res, 400, { status: 'error', errorCode: 'error_invalid_offering' });
}

function handleCreateOffering(practitioner, body, res) {
  const fields = validateOffering(body);
  if (!fields) {
    invalidOffering(res);
    return;
  }
  const offering = Object.assign(
    {
      id: crypto.randomUUID(),
      active: typeof body.active === 'boolean' ? body.active : true,
      createdAt: new Date().toISOString(),
    },
    fields
  );
  practitioner.offerings.push(offering);
  saveStore();
  sendJson(res, 201, offering);
}

function handleUpdateOffering(practitioner, offeringId, body, res) {
  const offering = practitioner.offerings.find((o) => o.id === offeringId);
  if (!offering) {
    notFound(res, 'error_offering_not_found', 'No such offering for this practitioner.');
    return;
  }
  const fields = validateOffering(body);
  if (!fields) {
    invalidOffering(res);
    return;
  }
  // Replace the editable fields — optional ones the body omits are dropped —
  // and keep the offering's identity (id, createdAt).
  for (const key of ['unit', 'durationMin', 'description']) delete offering[key];
  Object.assign(offering, fields);
  if (typeof body.active === 'boolean') offering.active = body.active;
  saveStore();
  sendJson(res, 200, offering);
}

function handleDeleteOffering(practitioner, offeringId, res) {
  const index = practitioner.offerings.findIndex((o) => o.id === offeringId);
  if (index === -1) {
    notFound(res, 'error_offering_not_found', 'No such offering for this practitioner.');
    return;
  }
  practitioner.offerings.splice(index, 1);
  saveStore();
  sendJson(res, 200, { ok: true });
}

// --- Practice logo (v2.1) ---------------------------------------------------

function logoFilePath(practitioner) {
  return practitioner.logo
    ? path.join(LOGOS_DIR, practitioner.id + '.' + practitioner.logo.ext)
    : null;
}

function handlePutLogo(practitioner, body, res) {
  const ext = body ? LOGO_EXT_BY_CONTENT_TYPE[body.contentType] : undefined;
  if (!ext) {
    sendJson(res, 400, { status: 'error', errorCode: 'error_logo_type' });
    return;
  }
  const buffer =
    typeof body.imageBase64 === 'string' ? decodeBase64Image(body.imageBase64) : null;
  if (!buffer) {
    sendJson(res, 400, { status: 'error', errorCode: 'error_logo_type' });
    return;
  }
  if (buffer.length > MAX_LOGO_BYTES) {
    sendJson(res, 413, { status: 'error', errorCode: 'error_logo_too_large' });
    return;
  }
  fs.mkdirSync(LOGOS_DIR, { recursive: true });
  const oldPath = logoFilePath(practitioner);
  const newPath = path.join(LOGOS_DIR, practitioner.id + '.' + ext);
  if (oldPath && oldPath !== newPath) {
    try {
      fs.unlinkSync(oldPath);
    } catch (_) {
      // Old logo file already gone — nothing to clean up.
    }
  }
  fs.writeFileSync(newPath, buffer);
  practitioner.logo = { ext, updatedAt: new Date().toISOString() };
  saveStore();
  sendJson(res, 200, publicPractitioner(practitioner));
}

function handleDeleteLogo(practitioner, res) {
  const filePath = logoFilePath(practitioner);
  if (filePath) {
    try {
      fs.unlinkSync(filePath);
    } catch (_) {
      // Logo file already gone — clearing the field is enough.
    }
  }
  practitioner.logo = null;
  saveStore();
  sendJson(res, 200, publicPractitioner(practitioner));
}

// Public: the client web page shows the logo without any credential.
function handleGetPublicLogo(practitionerId, res) {
  const practitioner = store.practitioners.find((p) => p.id === practitionerId);
  const filePath = practitioner ? logoFilePath(practitioner) : null;
  if (!practitioner || !filePath || !fs.existsSync(filePath)) {
    sendJson(res, 404, { status: 'error', errorCode: 'error_logo_not_found' });
    return;
  }
  const bytes = fs.readFileSync(filePath);
  res.writeHead(200, {
    'Content-Type': LOGO_CONTENT_TYPE_BY_EXT[practitioner.logo.ext] || 'application/octet-stream',
    'Content-Length': bytes.length,
    'Cache-Control': 'public, max-age=300',
  });
  res.end(bytes);
}

// --- Client-facing (token-keyed) handlers ---------------------------------

function handleGetPublicClient(token, res) {
  const found = findClientByToken(token);
  if (!found) {
    notFound(
      res,
      'error_client_not_found',
      'This link is not active. Ask your practitioner for your personal link.'
    );
    return;
  }
  const { practitioner, client } = found;
  sendJson(res, 200, {
    practitioner: {
      practiceName: practitioner.practiceName,
      practitionerName: practitioner.practitionerName,
      accent: practitioner.accent,
      bookingLink: practitioner.bookingLink,
      logoUrl: practitioner.logo
        ? '/api/practitioners/' + practitioner.id + '/logo'
        : null,
      offerings: (practitioner.offerings || []).filter((o) => o.active),
    },
    client: {
      firstName: client.firstName,
      account: client.account
        ? {
            email: client.account.email,
            emailVerified: !!client.account.emailVerified,
          }
        : null,
    },
    plan: client.plan || null,
    scans: client.scans.map((s) => ({
      label: s.label,
      timestamp: s.timestamp,
      result: s.result,
    })),
  });
}

async function handlePostClientScan(token, body, res) {
  const found = findClientByToken(token);
  if (!found) {
    notFound(res, 'error_client_not_found', 'This link is not active.');
    return;
  }
  // Simulated errors mirror the YouCam error surface so the client coaching
  // loop can rehearse before a real photo is sent. No provider call, no
  // units, nothing stored.
  if (typeof body.simulateError === 'string') {
    if (!SIMULATED_ERROR_CODES.includes(body.simulateError)) {
      badRequest(
        res,
        'simulateError must be "error_lighting_dark" or "error_src_face_too_small".'
      );
      return;
    }
    sendJson(res, 422, { status: 'error', errorCode: body.simulateError });
    return;
  }

  if (typeof body.imageBase64 === 'string' && body.imageBase64.trim()) {
    if (MODE !== 'live') {
      sendJson(res, 503, {
        status: 'error',
        errorCode: 'error_not_configured',
        message: 'This server has no YouCam API key configured, so scans are unavailable.',
      });
      return;
    }
    const buffer = decodeBase64Image(body.imageBase64);
    if (!buffer) {
      badRequest(res, 'imageBase64 must be valid base64-encoded JPEG or PNG data.');
      return;
    }
    const contentType = body.contentType === 'image/png' ? 'image/png' : 'image/jpeg';
    const taskId = startLiveScan(token, buffer, contentType);
    sendJson(res, 200, { taskId, status: 'running' });
    return;
  }

  badRequest(res, 'Send { "imageBase64": "..." } or { "simulateError": "..." }.');
}

function handleGetClientScan(token, taskId, res) {
  const record = liveTasks.get(taskId);
  // A task id is only visible to the client it belongs to.
  if (!record || record.clientToken !== token) {
    notFound(res, 'error_task_not_found', 'Unknown taskId for this client.');
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

function handleTry(body, res) {
  const sample = store.practitioners.find((p) => p.sample);
  if (!sample) {
    sendJson(res, 500, { status: 'error', errorCode: 'error_internal' });
    return;
  }
  const firstName = requireString(body || {}, 'firstName') || 'Guest';
  const client = {
    id: crypto.randomUUID(),
    token: newToken(),
    firstName,
    createdAt: new Date().toISOString(),
    oneOff: true,
    plan: null,
    scans: [],
  };
  sample.clients.push(client);
  saveStore();
  sendJson(res, 201, { token: client.token, link: '/?c=' + client.token });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

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

  // Read request bodies up front: answering an early error (401/404)
  // without consuming a POST/PUT body can reset the connection through
  // keep-alive proxies (observed via nginx: intermittent empty replies on
  // cross-owner PUTs). With the body drained first, every response is clean.
  let body = null;
  if (req.method === 'POST' || req.method === 'PUT') {
    body = await parseBody(req, res);
    if (body === null) return;
  }

  try {
    if (req.method === 'GET' && pathname === '/health') {
      sendJson(res, 200, { ok: true, mode: MODE });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/practitioners') {
      await handleCreatePractitioner(body, res);
      return;
    }

    if (req.method === 'POST' && pathname === '/api/login') {
      handleLogin(body, res);
      return;
    }

    if (req.method === 'POST' && pathname === '/api/try') {
      handleTry(body, res);
      return;
    }

    // Practitioner-scoped routes.
    if (pathname === '/api/me' || pathname.startsWith('/api/me/')) {
      const practitioner = authPractitioner(req);
      if (!practitioner) {
        unauthorized(res);
        return;
      }

      if (pathname === '/api/me' && req.method === 'GET') {
        sendJson(res, 200, publicPractitioner(practitioner));
        return;
      }
      if (pathname === '/api/me' && req.method === 'PUT') {
        editableProfile(body, practitioner);
        saveStore();
        sendJson(res, 200, publicPractitioner(practitioner));
        return;
      }
      if (pathname === '/api/me/account' && req.method === 'POST') {
        await handleSetAccount(practitioner, body, res);
        return;
      }
      if (pathname === '/api/me/offerings' && req.method === 'GET') {
        sendJson(res, 200, practitioner.offerings);
        return;
      }
      if (pathname === '/api/me/offerings' && req.method === 'POST') {
        handleCreateOffering(practitioner, body, res);
        return;
      }
      const offeringMatch = pathname.match(/^\/api\/me\/offerings\/([^/]+)$/);
      if (offeringMatch && req.method === 'PUT') {
        handleUpdateOffering(practitioner, decodeURIComponent(offeringMatch[1]), body, res);
        return;
      }
      if (offeringMatch && req.method === 'DELETE') {
        handleDeleteOffering(practitioner, decodeURIComponent(offeringMatch[1]), res);
        return;
      }
      if (pathname === '/api/me/logo' && req.method === 'PUT') {
        handlePutLogo(practitioner, body, res);
        return;
      }
      if (pathname === '/api/me/logo' && req.method === 'DELETE') {
        handleDeleteLogo(practitioner, res);
        return;
      }
      if (pathname === '/api/me/clients' && req.method === 'GET') {
        sendJson(res, 200, practitioner.clients.map(clientSummary));
        return;
      }
      if (pathname === '/api/me/clients' && req.method === 'POST') {
        handleCreateClient(practitioner, body, res);
        return;
      }

      const clientMatch = pathname.match(/^\/api\/me\/clients\/([^/]+)$/);
      if (clientMatch) {
        const client = ownClientOr404(practitioner, decodeURIComponent(clientMatch[1]), res);
        if (!client) return;
        if (req.method === 'GET') {
          sendJson(res, 200, clientFull(client));
          return;
        }
        if (req.method === 'DELETE') {
          practitioner.clients = practitioner.clients.filter((c) => c.id !== client.id);
          saveStore();
          sendJson(res, 200, { ok: true });
          return;
        }
        sendJson(res, 405, { status: 'error', errorCode: 'error_method_not_allowed' });
        return;
      }

      const planMatch = pathname.match(/^\/api\/me\/clients\/([^/]+)\/plan$/);
      if (planMatch && req.method === 'PUT') {
        const client = ownClientOr404(practitioner, decodeURIComponent(planMatch[1]), res);
        if (!client) return;
        if (typeof body.plan !== 'object' || body.plan === null) {
          badRequest(res, 'plan must be a JSON object.');
          return;
        }
        client.plan = body.plan;
        saveStore();
        sendJson(res, 200, clientSummary(client));
        return;
      }

      sendJson(res, 404, { status: 'error', errorCode: 'error_not_found' });
      return;
    }

    // Accounts (v2.2): public verification / recovery endpoints.
    if (req.method === 'POST' && pathname === '/api/auth/verify-email') {
      handleVerifyEmail(body, res);
      return;
    }
    if (req.method === 'POST' && pathname === '/api/auth/resend-verification') {
      await handleResendVerification(body, res);
      return;
    }
    if (req.method === 'POST' && pathname === '/api/auth/forgot-password') {
      await handleForgotPassword(body, res);
      return;
    }
    if (req.method === 'POST' && pathname === '/api/auth/reset-password') {
      handleResetPassword(body, res);
      return;
    }
    if (req.method === 'POST' && pathname === '/api/clients/signin') {
      handleClientSignin(body, res);
      return;
    }

    // Public practitioner logo (the client page displays it; no auth).
    const publicLogoMatch = pathname.match(/^\/api\/practitioners\/([^/]+)\/logo$/);
    if (publicLogoMatch && req.method === 'GET') {
      handleGetPublicLogo(decodeURIComponent(publicLogoMatch[1]), res);
      return;
    }

    // Client-facing routes (token-keyed).
    const publicClientMatch = pathname.match(/^\/api\/clients\/([^/]+)$/);
    if (publicClientMatch && req.method === 'GET') {
      handleGetPublicClient(decodeURIComponent(publicClientMatch[1]), res);
      return;
    }
    const clientScanMatch = pathname.match(/^\/api\/clients\/([^/]+)\/scans$/);
    if (clientScanMatch && req.method === 'POST') {
      await handlePostClientScan(decodeURIComponent(clientScanMatch[1]), body, res);
      return;
    }
    const clientAccountMatch = pathname.match(/^\/api\/clients\/([^/]+)\/account$/);
    if (clientAccountMatch && req.method === 'POST') {
      await handleCreateClientAccount(
        decodeURIComponent(clientAccountMatch[1]),
        body,
        res
      );
      return;
    }
    const clientTaskMatch = pathname.match(/^\/api\/clients\/([^/]+)\/scans\/([^/]+)$/);
    if (clientTaskMatch && req.method === 'GET') {
      handleGetClientScan(
        decodeURIComponent(clientTaskMatch[1]),
        decodeURIComponent(clientTaskMatch[2]),
        res
      );
      return;
    }

    sendJson(res, 404, { status: 'error', errorCode: 'error_not_found' });
  } catch (err) {
    console.error('[estiseries] request failed:', err && err.message ? err.message : err);
    if (!res.headersSent) {
      sendJson(res, 500, { status: 'error', errorCode: 'error_internal' });
    }
  }
});

server.listen(PORT, () => {
  console.log(
    '[estiseries] backend listening on http://localhost:' + PORT + ' (' + MODE + ' mode)'
  );
  console.log('[estiseries] mail transport: ' + MAIL_TRANSPORT);
  if (MODE !== 'live') {
    console.log(
      '[estiseries] WARNING: no YOUCAM_API_KEY set — store endpoints work, scans return error_not_configured.'
    );
  } else {
    console.log('[estiseries] live mode — YOUCAM_API_KEY is set; scans run against YouCam.');
  }
});
