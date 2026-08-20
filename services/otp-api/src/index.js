import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express from 'express';
import { Resend } from 'resend';

import {
  otpEmailHtml,
  otpEmailText,
  riderWelcomeEmailHtml,
  riderWelcomeEmailText,
} from './emails/templates.js';
import {
  createRiderCustomToken,
  hasFirebaseAdmin,
} from './firebase-admin.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(__dirname, '../public');

const app = express();
const port = Number(process.env.PORT || 8787);

const resendApiKey = process.env.RESEND_API_KEY?.trim() || '';
const fromEmail =
  process.env.OTP_FROM_EMAIL?.trim() || 'CitiRide <onboarding@resend.dev>';
const otpTtlMs = Number(process.env.OTP_TTL_MS || 10 * 60 * 1000);
const maxAttempts = Number(process.env.OTP_MAX_ATTEMPTS || 5);
const resendCooldownMs = Number(process.env.OTP_RESEND_COOLDOWN_MS || 30 * 1000);
const demoMode =
  process.env.OTP_DEMO_MODE === 'true' ||
  (!resendApiKey && process.env.NODE_ENV !== 'production');
const demoCode = process.env.OTP_DEMO_CODE?.trim() || '968999';

const resend = resendApiKey ? new Resend(resendApiKey) : null;

/** @type {Map<string, { hash: string, salt: string, expiresAt: number, attempts: number, lastSentAt: number }>} */
const otpStore = new Map();

/** Avoid spamming welcome mail on repeated logins in a short window. */
/** @type {Map<string, number>} email -> last successful welcome send (ms) */
const welcomeSentAt = new Map();
const welcomeCooldownMs = Number(
  process.env.OTP_WELCOME_COOLDOWN_MS || 24 * 60 * 60 * 1000,
);

app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.use('/assets', express.static(publicDir, { maxAge: '7d' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    demoMode,
    hasResendKey: Boolean(resendApiKey),
    hasFirebaseAdmin: hasFirebaseAdmin(),
    emailTheme: 'branded-light-v2',
    emailSubject: 'Your CitiRide one-time password',
  });
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
    const existing = otpStore.get(key);
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

    otpStore.set(key, {
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
        subject: 'Your CitiRide one-time password',
        html: otpEmailHtml({ code, purpose, ttlMinutes }),
        text: otpEmailText({ code, purpose, ttlMinutes }),
      });

      if (error) {
        otpStore.delete(key);
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
    const record = otpStore.get(key);

    if (!record) {
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    if (Date.now() > record.expiresAt) {
      otpStore.delete(key);
      return res.status(400).json({
        error: 'session-expired',
        message: 'Verification session expired. Please request a new code.',
      });
    }

    if (record.attempts >= maxAttempts) {
      otpStore.delete(key);
      return res.status(429).json({
        error: 'too-many-attempts',
        message: 'Too many incorrect attempts. Please request a new code.',
      });
    }

    const incomingHash = hashOtp(code, record.salt);
    if (incomingHash !== record.hash) {
      record.attempts += 1;
      otpStore.set(key, record);
      return res.status(400).json({
        error: 'invalid-verification-code',
        message: 'Incorrect code',
      });
    }

    otpStore.delete(key);

    let welcomeEmail = 'skipped';
    if (purpose === 'login') {
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

app.listen(port, () => {
  console.log(
    `CitiRide OTP API listening on :${port} (demoMode=${demoMode}, hasResendKey=${Boolean(resendApiKey)}, hasFirebaseAdmin=${hasFirebaseAdmin()})`,
  );
});

/**
 * @returns {Promise<'sent' | 'skipped' | 'failed'>}
 */
async function sendRiderWelcomeEmail(email) {
  // Welcome mail needs Resend. Do not tie it to OTP demoMode — demoMode only
  // controls whether the 6-digit code is emailed.
  if (!resend) {
    console.warn('welcome email skipped: Resend is not configured');
    return 'skipped';
  }

  const lastSentAt = welcomeSentAt.get(email) || 0;
  if (Date.now() - lastSentAt < welcomeCooldownMs) {
    console.info('welcome email skipped: cooldown', email);
    return 'skipped';
  }

  try {
    const { error } = await resend.emails.send({
      from: fromEmail,
      to: [email],
      subject: 'Welcome to CitiRide',
      html: riderWelcomeEmailHtml({ email }),
      text: riderWelcomeEmailText({ email }),
    });

    if (error) {
      console.error('welcome email failed', error);
      return 'failed';
    }

    welcomeSentAt.set(email, Date.now());
    console.info('welcome email sent', email);
    return 'sent';
  } catch (error) {
    console.error('welcome email failed', error);
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

function normalizePurpose(value) {
  const purpose = String(value || 'login')
    .trim()
    .toLowerCase();
  if (['login', 'wallet', 'reset_pin', 'withdraw'].includes(purpose)) {
    return purpose;
  }
  return 'login';
}

function storeKey(email, purpose) {
  return `${purpose}:${email}`;
}

function generateOtp() {
  return String(crypto.randomInt(100000, 1000000));
}

function hashOtp(code, salt) {
  return crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');
}
