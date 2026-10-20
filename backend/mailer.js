'use strict';

// EstiSeries mailer — zero-dependency outbound mail for account
// verification and password recovery (contract v2.2).
//
// Transports, selected once from the environment:
//   MAIL_TRANSPORT=capture   -> append each message as a JSON line to
//                               MAIL_CAPTURE_PATH (tests read tokens back
//                               out of the captured links; nothing is sent)
//   MAIL_TRANSPORT=smtp      -> direct SMTP (implicit TLS on port 465,
//                               STARTTLS otherwise; AUTH LOGIN)
//   MAIL_TRANSPORT=sendmail  -> the host's /usr/sbin/sendmail binary
//   (unset)                  -> smtp when SMTP_HOST is set, else sendmail
//                               when the binary exists, else capture to a
//                               file beside the data store with a warning
// Configuration comes ONLY from environment variables (backend/.env in
// production): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, MAIL_FROM.
// No credential is ever logged.

const fs = require('node:fs');
const net = require('node:net');
const tls = require('node:tls');
const { spawn } = require('node:child_process');

const MAIL_FROM = process.env.MAIL_FROM || 'no-reply@estiseries.ignisalgos.com';
const CAPTURE_PATH =
  process.env.MAIL_CAPTURE_PATH ||
  (process.env.DATA_PATH
    ? process.env.DATA_PATH + '.mail-capture.jsonl'
    : '/tmp/estiseries-mail-capture.jsonl');

function selectTransport() {
  const forced = (process.env.MAIL_TRANSPORT || '').trim().toLowerCase();
  if (forced === 'capture' || forced === 'smtp' || forced === 'sendmail') return forced;
  if (process.env.SMTP_HOST && process.env.SMTP_HOST.trim()) return 'smtp';
  try {
    if (fs.existsSync('/usr/sbin/sendmail')) return 'sendmail';
  } catch (_) {
    // fall through to capture
  }
  return 'capture';
}

const TRANSPORT = selectTransport();

// ---- capture ---------------------------------------------------------------

function sendCapture({ to, subject, text }) {
  const line =
    JSON.stringify({ to, subject, text, transport: 'capture', at: new Date().toISOString() }) +
    '\n';
  fs.appendFileSync(CAPTURE_PATH, line);
  return Promise.resolve({ ok: true, transport: 'capture' });
}

// ---- sendmail --------------------------------------------------------------

function sendViaSendmail({ to, subject, text }) {
  return new Promise((resolve) => {
    const message = [
      'From: EstiSeries <' + MAIL_FROM + '>',
      'To: ' + to,
      'Subject: ' + subject,
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      text,
      '',
    ].join('\r\n');
    let child;
    try {
      child = spawn('/usr/sbin/sendmail', ['-f', MAIL_FROM, to], {
        stdio: ['pipe', 'ignore', 'pipe'],
      });
    } catch (err) {
      resolve({ ok: false, transport: 'sendmail', error: String(err && err.message) });
      return;
    }
    let stderr = '';
    child.stderr.on('data', (d) => {
      stderr += d.toString();
    });
    child.on('error', (err) =>
      resolve({ ok: false, transport: 'sendmail', error: String(err && err.message) })
    );
    child.on('close', (code) => {
      if (code === 0) resolve({ ok: true, transport: 'sendmail' });
      else
        resolve({
          ok: false,
          transport: 'sendmail',
          error: 'sendmail exited ' + code + (stderr ? ': ' + stderr.trim().slice(0, 200) : ''),
        });
    });
    child.stdin.end(message);
  });
}

// ---- smtp ------------------------------------------------------------------
// Minimal SMTP client: EHLO, optional STARTTLS, AUTH LOGIN, one message.
// Good enough for a transactional trickle and dependency-free by design.

function smtpReadLine(socket, buffer) {
  return new Promise((resolve, reject) => {
    let data = buffer.carry || '';
    const onData = (chunk) => {
      data += chunk.toString('utf8');
      // A reply is complete at a line "NNN " (space after the code).
      const match = data.match(/(^|\r\n)(\d{3}) ([^\r\n]*)/);
      if (match) {
        socket.off('data', onData);
        resolve({ code: Number(match[2]), line: match[3], rest: data });
      }
    };
    socket.on('data', onData);
    socket.once('error', reject);
    if (data) onData(Buffer.from(''));
  });
}

async function smtpExpect(socket, want, what) {
  const reply = await smtpReadLine(socket, {});
  if (reply.code !== want) {
    throw new Error('SMTP ' + what + ' failed: ' + reply.code + ' ' + reply.line);
  }
  return reply;
}

function smtpWrite(socket, line) {
  return new Promise((resolve, reject) => {
    socket.write(line + '\r\n', (err) => (err ? reject(err) : resolve()));
  });
}

async function sendViaSmtp({ to, subject, text }) {
  const host = process.env.SMTP_HOST.trim();
  const port = Number.parseInt(process.env.SMTP_PORT || '', 10) || 587;
  const user = process.env.SMTP_USER || '';
  const pass = process.env.SMTP_PASS || '';
  const implicitTls = port === 465;

  let socket = implicitTls
    ? tls.connect({ host, port, servername: host })
    : net.connect({ host, port });
  socket.setTimeout(20000, () => socket.destroy(new Error('SMTP timeout')));

  try {
    await new Promise((resolve, reject) => {
      socket.once(implicitTls ? 'secureConnect' : 'connect', resolve);
      socket.once('error', reject);
    });
    await smtpExpect(socket, 220, 'greeting');
    await smtpWrite(socket, 'EHLO estiseries.ignisalgos.com');
    let reply = await smtpReadLine(socket, {});

    if (!implicitTls && /STARTTLS/.test(reply.rest || '')) {
      await smtpWrite(socket, 'STARTTLS');
      await smtpExpect(socket, 220, 'STARTTLS');
      socket = tls.connect({ socket, servername: host });
      await new Promise((resolve, reject) => {
        socket.once('secureConnect', resolve);
        socket.once('error', reject);
      });
      await smtpWrite(socket, 'EHLO estiseries.ignisalgos.com');
      await smtpReadLine(socket, {});
    }

    if (user) {
      await smtpWrite(socket, 'AUTH LOGIN');
      await smtpExpect(socket, 334, 'AUTH');
      await smtpWrite(socket, Buffer.from(user, 'utf8').toString('base64'));
      await smtpExpect(socket, 334, 'AUTH user');
      await smtpWrite(socket, Buffer.from(pass, 'utf8').toString('base64'));
      await smtpExpect(socket, 235, 'AUTH password');
    }

    await smtpWrite(socket, 'MAIL FROM:<' + MAIL_FROM + '>');
    await smtpExpect(socket, 250, 'MAIL FROM');
    await smtpWrite(socket, 'RCPT TO:<' + to + '>');
    await smtpExpect(socket, 250, 'RCPT TO');
    await smtpWrite(socket, 'DATA');
    await smtpExpect(socket, 354, 'DATA');
    const message = [
      'From: EstiSeries <' + MAIL_FROM + '>',
      'To: ' + to,
      'Subject: ' + subject,
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      text.replace(/\r\n/g, '\n').replace(/\n\./g, '\n..'),
      '.',
    ].join('\r\n');
    await smtpWrite(socket, message);
    await smtpExpect(socket, 250, 'message body');
    await smtpWrite(socket, 'QUIT');
    socket.end();
    return { ok: true, transport: 'smtp' };
  } catch (err) {
    try {
      socket.destroy();
    } catch (_) {
      // already gone
    }
    return { ok: false, transport: 'smtp', error: String(err && err.message) };
  }
}

// ---- public API --------------------------------------------------------------

async function sendMail(message) {
  try {
    if (TRANSPORT === 'smtp') return await sendViaSmtp(message);
    if (TRANSPORT === 'sendmail') return await sendViaSendmail(message);
    return await sendCapture(message);
  } catch (err) {
    return { ok: false, transport: TRANSPORT, error: String(err && err.message) };
  }
}

module.exports = { sendMail, TRANSPORT, MAIL_FROM };
