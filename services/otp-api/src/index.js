import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express from 'express';
import { Resend } from 'resend';

import {
  otpEmailCopy,
  otpEmailHtml,
  otpEmailText,
  driverWelcomeEmailHtml,
  driverWelcomeEmailText,
  riderWelcomeEmailHtml,
  riderWelcomeEmailText,
  riderWalletCreatedEmailHtml,
  riderWalletCreatedEmailText,
  driverWalletCreatedEmailHtml,
  driverWalletCreatedEmailText,
} from './emails/templates.js';
import { handleDriverPhotoUpload } from './driver-photo.js';
import {
  admin,
  createDriverCustomToken,
  createRiderCustomToken,
  driverAccountExists,
  hasFirebaseAdmin,
  riderAccountExists,
} from './firebase-admin.js';
import { hasPaystack } from './paystack/client.js';
import { handlePaystackWebhook, walletRouter } from './wallet/routes.js';
import { tripNavigationRouter } from './trip-navigation.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(__dirname, '../public');

const app = express();
const port = Number(process.env.PORT || 8787);

const resendApiKey = process.env.RESEND_API_KEY?.trim() || '';
const fromEmail =
  process.env.OTP_FROM_EMAIL?.trim() || 'CitiRide <onboarding@resend.dev>';
const otpTtlMs = Number(process.env.OTP_TTL_MS || 10 * 60 * 1000);
const maxAttempts = Number(process.env.OTP_MAX_ATTEMPTS || 5);
const resendCooldownMs = Number(process.env.OTP_RESEND_COOLDOWN_MS || 40 * 1000);
const demoMode =
  process.env.OTP_DEMO_MODE === 'true' ||
  (!resendApiKey && process.env.NODE_ENV !== 'production');
const demoCode = process.env.OTP_DEMO_CODE?.trim() || '968999';

const resend = resendApiKey ? new Resend(resendApiKey) : null;

const OTP_SESSIONS = 'otp_sessions';

/**
 * Local-development fallback only. Production sessions are persisted in
 * Firestore so send and verify requests can safely reach different replicas.
 * @type {Map<string, { hash: string, salt: string, expiresAt: number, attempts: number, lastSentAt: number }>}
 */
const otpStore = new Map();

/** Avoid spamming welcome mail on repeated logins in a short window. */
/** @type {Map<string, number>} email -> last successful welcome send (ms) */
const welcomeSentAt = new Map();
/** @type {Map<string, number>} driver email -> last successful driver welcome send (ms) */
const driverWelcomeSentAt = new Map();
/** @type {Map<string, number>} email -> last wallet congratulations send (ms) */
const riderWalletCreatedSentAt = new Map();
/** @type {Map<string, number>} driver email -> last wallet congratulations send (ms) */
const driverWalletCreatedSentAt = new Map();
const welcomeCooldownMs = Number(
  process.env.OTP_WELCOME_COOLDOWN_MS || 24 * 60 * 60 * 1000,
);

app.use(cors());
const jsonParser = express.json({
  limit: '64kb',
  verify: (req, _res, buf) => {
    req.rawBody = buf;
  },
});
app.use((req, res, next) => {
  if (req.path === '/v1/driver/photo') {
    return next();
  }
  return jsonParser(req, res, next);
});
app.post(
  '/v1/driver/photo',
  express.json({ limit: '6mb' }),
  (req, res, next) => {
    handleDriverPhotoUpload(req, res).catch(next);
  },
);
app.use('/assets', express.static(publicDir, { maxAge: '7d' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    demoMode,
    hasResendKey: Boolean(resendApiKey),
    hasFirebaseAdmin: hasFirebaseAdmin(),
    hasPaystack: hasPaystack(),
    emailTheme: 'branded-light-v2',
    emailSubject: 'Your CitiRide one-time password',
  });
});

app.use('/v1/wallet', walletRouter);
app.use('/v1/trips', tripNavigationRouter);
app.post('/v1/paystack/webhook', (req, res) => {
  // Prefer raw buffer captured by express.json verify hook.
  if (!Buffer.isBuffer(req.body) && req.rawBody) {
    req.body = req.rawBody;
  }
  return handlePaystackWebhook(req, res);
});

app.get('/v1/email-preview', (_req, res) => {
  const html = otpEmailHtml({
    code: '332922',
    purpose: 'login',
    ttlMinutes: Math.round(otpTtlMs / 60000),
  });
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});

app.post('/v1/otp/account-status', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }
    const exists = await riderAccountExists(email);
    return res.json({ ok: true, email, exists, role: 'rider' });
  } catch (error) {
    console.error('rider account status failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to check this email. Please try again.',
    });
  }
});

app.post('/v1/driver/otp/account-status', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }
    const exists = await driverAccountExists(email);
    return res.json({ ok: true, email, exists, role: 'driver' });
  } catch (error) {
    console.error('driver account status failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to check this email. Please try again.',
    });
  }
});

app.post('/v1/otp/send', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const purpose = normalizePurpose(req.body?.purpose);

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    const key = storeKey(email, purpose);
    const existing = await getOtpRecord(key);
    const now = Date.now();

    if (existing && now - existing.lastSentAt < resendCooldownMs) {
      const retryAfterMs = resendCooldownMs - (now - existing.lastSentAt);
      return res.status(429).json({
        error: 'cooldown',
        message: 'Please wait a moment before requesting another code.',
        retryAfterMs,
      });
    }

    const code = demoMode ? demoCode : generateOtp();
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashOtp(code, salt);

    await saveOtpRecord(key, {
      hash,
      salt,
      expiresAt: now + otpTtlMs,
      attempts: 0,
      lastSentAt: now,
    });

    if (!demoMode) {
      if (!resend) {
        return res.status(500).json({
          error: 'misconfigured',
          message: 'RESEND_API_KEY is not configured.',
        });
      }

      const ttlMinutes = Math.round(otpTtlMs / 60000);
      const { error } = await resend.emails.send({
        from: fromEmail,
        to: [email],
        subject: otpEmailCopy(purpose).subject,
        html: otpEmailHtml({ code, purpose, ttlMinutes }),
        text: otpEmailText({ code, purpose, ttlMinutes }),
      });

      if (error) {
        await deleteOtpRecord(key);
        return res.status(502).json({
          error: 'send_failed',
          message: error.message || 'Unable to send verification email.',
        });
      }
    }

    return res.json({
      ok: true,
      email,
      purpose,
      expiresInMs: otpTtlMs,
      demoMode,
      ...(demoMode ? { demoCode } : {}),
    });
  } catch (error) {
    console.error('send otp failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to send verification code. Please try again.',
    });
  }
});

app.post('/v1/otp/verify', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const purpose = normalizePurpose(req.body?.purpose);
    const code = String(req.body?.code || '').trim();

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    if (!/^\d{6}$/.test(code)) {
      return res.status(400).json({
        error: 'invalid_code_format',
        message: 'Enter the 6-digit verification code.',
      });
    }

    const key = storeKey(email, purpose);
    const verification = await verifyOtpRecord(key, code);

    if (verification.status === 'missing') {
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    if (verification.status === 'expired') {
      return res.status(400).json({
        error: 'session-expired',
        message: 'Verification session expired. Please request a new code.',
      });
    }

    if (verification.status === 'locked') {
      return res.status(429).json({
        error: 'too-many-attempts',
        message: 'Too many incorrect attempts. Please request a new code.',
      });
    }

    if (verification.status === 'invalid') {
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    let welcomeEmail = 'skipped';
    if (purpose === 'signup' || purpose === 'login') {
      welcomeEmail = await sendRiderWelcomeEmail(email);
    }

    let firebaseCustomToken = null;
    try {
      // Mint for login so the Flutter app can open a Firebase Auth session.
      // Also mint for other purposes so a cold app can recover auth mid-flow.
      firebaseCustomToken = await createRiderCustomToken(email);
    } catch (tokenError) {
      console.error('custom token failed', tokenError);
    }

    return res.json({
      ok: true,
      email,
      purpose,
      verified: true,
      welcomeEmail,
      ...(firebaseCustomToken ? { firebaseCustomToken } : {}),
    });
  } catch (error) {
    console.error('verify otp failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to verify code. Please try again.',
    });
  }
});

/** Driver app (React Native): send OTP scoped to driver login or signup. */
app.post('/v1/driver/otp/send', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const authIntent = normalizeAuthIntent(
      req.body?.intent ?? req.body?.purpose,
    );
    const emailPurpose =
      authIntent === 'signup' ? 'driver_signup' : 'driver_login';
    const purpose = 'driver_login';

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    const key = storeKey(email, purpose);
    const existing = await getOtpRecord(key);
    const now = Date.now();

    if (existing && now - existing.lastSentAt < resendCooldownMs) {
      const retryAfterMs = resendCooldownMs - (now - existing.lastSentAt);
      return res.status(429).json({
        error: 'cooldown',
        message: 'Please wait a moment before requesting another code.',
        retryAfterMs,
      });
    }

    const code = demoMode ? demoCode : generateOtp();
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashOtp(code, salt);

    await saveOtpRecord(key, {
      hash,
      salt,
      expiresAt: now + otpTtlMs,
      attempts: 0,
      lastSentAt: now,
    });

    if (!demoMode) {
      if (!resend) {
        return res.status(500).json({
          error: 'misconfigured',
          message: 'RESEND_API_KEY is not configured.',
        });
      }

      const ttlMinutes = Math.round(otpTtlMs / 60000);
      const { error } = await resend.emails.send({
        from: fromEmail,
        to: [email],
        subject: otpEmailCopy(emailPurpose).subject,
        html: otpEmailHtml({ code, purpose: emailPurpose, ttlMinutes }),
        text: otpEmailText({ code, purpose: emailPurpose, ttlMinutes }),
      });

      if (error) {
        await deleteOtpRecord(key);
        return res.status(502).json({
          error: 'send_failed',
          message: error.message || 'Unable to send verification email.',
        });
      }
    }

    return res.json({
      ok: true,
      email,
      purpose: 'driver_login',
      role: 'driver',
      expiresInMs: otpTtlMs,
      demoMode,
      ...(demoMode ? { demoCode } : {}),
    });
  } catch (error) {
    console.error('driver send otp failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to send verification code. Please try again.',
    });
  }
});

/** Driver app (React Native): verify OTP and mint Firebase custom token. */
app.post('/v1/driver/otp/verify', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const purpose = 'driver_login';
    const code = String(req.body?.code || '').trim();

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    if (!/^\d{6}$/.test(code)) {
      return res.status(400).json({
        error: 'invalid_code_format',
        message: 'Enter the 6-digit verification code.',
      });
    }

    const key = storeKey(email, purpose);
    const verification = await verifyOtpRecord(key, code);

    if (verification.status === 'missing') {
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    if (verification.status === 'expired') {
      return res.status(400).json({
        error: 'session-expired',
        message: 'Verification session expired. Please request a new code.',
      });
    }

    if (verification.status === 'locked') {
      return res.status(429).json({
        error: 'too-many-attempts',
        message: 'Too many incorrect attempts. Please request a new code.',
      });
    }

    if (verification.status === 'invalid') {
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    let firebaseCustomToken = null;
    let driverId = null;
    try {
      const minted = await createDriverCustomToken(email);
      if (minted) {
        firebaseCustomToken = minted.token;
        driverId = minted.uid;
      }
    } catch (tokenError) {
      console.error('driver custom token failed', tokenError);
    }

    const welcomeEmail = await sendDriverWelcomeEmail(email);

    return res.json({
      ok: true,
      email,
      purpose: 'driver_login',
      role: 'driver',
      verified: true,
      driverId,
      welcomeEmail,
      ...(firebaseCustomToken ? { firebaseCustomToken } : {}),
    });
  } catch (error) {
    console.error('driver verify otp failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to verify code. Please try again.',
    });
  }
});

/**
 * Sent after wallet passcode enrollment completes (rider or driver app).
 * Body: { email, role?: "rider" | "driver" }
 */
app.post('/v1/wallet/congratulate', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const role =
      String(req.body?.role || 'rider').trim().toLowerCase() === 'driver'
        ? 'driver'
        : 'rider';

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    const status =
      role === 'driver'
        ? await sendDriverWalletCreatedEmail(email)
        : await sendRiderWalletCreatedEmail(email);

    return res.json({
      ok: true,
      email,
      role,
      walletEmail: status,
    });
  } catch (error) {
    console.error('wallet congratulate failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to send wallet congratulations email.',
    });
  }
});

/**
 * Explicit driver welcome send (used if verify-time welcome failed/skipped).
 * Body: { email, force?: boolean }
 */
app.post('/v1/driver/welcome', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const force = Boolean(req.body?.force);

    if (!email) {
      return res.status(400).json({
        error: 'invalid_email',
        message: 'Enter a valid email address.',
      });
    }

    if (force) {
      driverWelcomeSentAt.delete(email);
    }

    const welcomeEmail = await sendDriverWelcomeEmail(email);
    return res.json({
      ok: true,
      email,
      role: 'driver',
      welcomeEmail,
    });
  } catch (error) {
    console.error('driver welcome failed', error);
    return res.status(500).json({
      error: 'server_error',
      message: 'Unable to send driver welcome email.',
    });
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  if (res.headersSent) {
    return;
  }
  res.status(500).json({
    error: 'server_error',
    message: 'Please try again.',
  });
});

app.listen(port, () => {
  console.log(
    `CitiRide OTP API listening on :${port} (demoMode=${demoMode}, hasResendKey=${Boolean(resendApiKey)}, hasFirebaseAdmin=${hasFirebaseAdmin()})`,
  );
});

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendRiderWelcomeEmail(email) {
  return sendWelcomeEmail({
    email,
    sentAtMap: welcomeSentAt,
    subject: 'Welcome to CitiRide',
    html: riderWelcomeEmailHtml({ email }),
    text: riderWelcomeEmailText({ email }),
    logLabel: 'rider welcome email',
  });
}

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendDriverWelcomeEmail(email) {
  return sendWelcomeEmail({
    email,
    sentAtMap: driverWelcomeSentAt,
    subject: 'Welcome to CitiRide Driver',
    html: driverWelcomeEmailHtml({ email }),
    text: driverWelcomeEmailText({ email }),
    logLabel: 'driver welcome email',
  });
}

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendRiderWalletCreatedEmail(email) {
  return sendWelcomeEmail({
    email,
    sentAtMap: riderWalletCreatedSentAt,
    subject: 'Congratulations — your CitiRide wallet is ready',
    html: riderWalletCreatedEmailHtml({ email }),
    text: riderWalletCreatedEmailText({ email }),
    logLabel: 'rider wallet created email',
  });
}

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendDriverWalletCreatedEmail(email) {
  return sendWelcomeEmail({
    email,
    sentAtMap: driverWalletCreatedSentAt,
    subject: 'Congratulations — your CitiRide driver wallet is ready',
    html: driverWalletCreatedEmailHtml({ email }),
    text: driverWalletCreatedEmailText({ email }),
    logLabel: 'driver wallet created email',
  });
}

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendWelcomeEmail({ email, sentAtMap, subject, html, text, logLabel }) {
  // Welcome mail needs Resend. Do not tie it to OTP demoMode — demoMode only
  // controls whether the 6-digit code is emailed.
  if (!resend) {
    console.warn(`${logLabel} skipped: Resend is not configured`);
    return 'skipped';
  }

  const lastSentAt = sentAtMap.get(email) || 0;
  if (Date.now() - lastSentAt < welcomeCooldownMs) {
    console.info(`${logLabel} skipped: cooldown`, email);
    return 'skipped';
  }

  try {
    const { error } = await resend.emails.send({
      from: fromEmail,
      to: [email],
      subject,
      html,
      text,
    });

    if (error) {
      console.error(`${logLabel} failed`, error);
      return 'failed';
    }

    sentAtMap.set(email, Date.now());
    console.info(`${logLabel} sent`, email);
    return 'sent';
  } catch (error) {
    console.error(`${logLabel} failed`, error);
    return 'failed';
  }
}

function normalizeEmail(value) {
  const email = String(value || '')
    .trim()
    .toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return null;
  }
  return email;
}

function normalizeAuthIntent(value) {
  const intent = String(value || '')
    .trim()
    .toLowerCase();
  if (
    intent === 'login' ||
    intent === 'log-in' ||
    intent === 'log_in' ||
    intent === 'driver_login'
  ) {
    return 'login';
  }
  return 'signup';
}

function normalizePurpose(value) {
  const purpose = String(value || 'login')
    .trim()
    .toLowerCase();
  if (
    [
      'login',
      'signup',
      'wallet',
      'reset_pin',
      'withdraw',
      'driver_login',
      'driver_signup',
    ].includes(purpose)
  ) {
    return purpose;
  }
  return 'login';
}

function storeKey(email, purpose) {
  const bucket =
    purpose === 'signup'
      ? 'login'
      : purpose === 'driver_signup'
        ? 'driver_login'
        : purpose;
  return `${bucket}:${email}`;
}

function otpSessionId(key) {
  // Do not expose an email address in the Firestore document ID.
  return crypto.createHash('sha256').update(key).digest('hex');
}

function otpSessionRef(key) {
  if (!hasFirebaseAdmin()) return null;
  return admin.firestore().collection(OTP_SESSIONS).doc(otpSessionId(key));
}

async function getOtpRecord(key) {
  const ref = otpSessionRef(key);
  if (!ref) return otpStore.get(key) || null;

  const snap = await ref.get();
  return snap.exists ? snap.data() : null;
}

async function saveOtpRecord(key, record) {
  const ref = otpSessionRef(key);
  if (!ref) {
    otpStore.set(key, record);
    return;
  }

  await ref.set({
    hash: record.hash,
    salt: record.salt,
    expiresAt: Number(record.expiresAt),
    attempts: Number(record.attempts || 0),
    lastSentAt: Number(record.lastSentAt),
    updatedAt: new Date(),
  });
}

async function deleteOtpRecord(key) {
  const ref = otpSessionRef(key);
  if (!ref) {
    otpStore.delete(key);
    return;
  }
  await ref.delete();
}

function inspectOtpRecord(record, code) {
  if (!record) return 'missing';
  if (Date.now() > Number(record.expiresAt || 0)) return 'expired';
  if (Number(record.attempts || 0) >= maxAttempts) return 'locked';
  return hashOtp(code, String(record.salt || '')) === String(record.hash || '')
    ? 'verified'
    : 'invalid';
}

/**
 * Atomically verify and consume an OTP. Firestore prevents two replicas from
 * accepting the same code or losing the wrong-attempt count.
 */
async function verifyOtpRecord(key, code) {
  const ref = otpSessionRef(key);
  if (!ref) {
    const record = otpStore.get(key);
    const status = inspectOtpRecord(record, code);
    if (status === 'verified' || status === 'expired' || status === 'locked') {
      otpStore.delete(key);
    } else if (status === 'invalid' && record) {
      record.attempts = Number(record.attempts || 0) + 1;
      otpStore.set(key, record);
    }
    return { status };
  }

  return admin.firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const record = snap.exists ? snap.data() : null;
    const status = inspectOtpRecord(record, code);

    if (status === 'verified' || status === 'expired' || status === 'locked') {
      transaction.delete(ref);
    } else if (status === 'invalid' && record) {
      transaction.update(ref, {
        attempts: Number(record.attempts || 0) + 1,
        updatedAt: new Date(),
      });
    }

    return { status };
  });
}

function generateOtp() {
  return String(crypto.randomInt(100000, 1000000));
}

function hashOtp(code, salt) {
  return crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');
}
