import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express from 'express';
import { Resend } from 'resend';

import {
  logoAttachment,
  otpEmailHtml,
  otpEmailText,
  riderWelcomeEmailHtml,
  riderWelcomeEmailText,
} from './emails/templates.js';

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

/** Avoid spamming welcome mail on repeated logins in the same process. */
const welcomeSent = new Set();

app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.use('/assets', express.static(publicDir, { maxAge: '7d' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    demoMode,
    hasResendKey: Boolean(resendApiKey),
  });
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
      const logo = logoAttachment();
      const { error } = await resend.emails.send({
        from: fromEmail,
        to: [email],
        subject: 'Your CitiRide verification code',
        html: otpEmailHtml({ code, purpose, ttlMinutes }),
        text: otpEmailText({ code, purpose, ttlMinutes }),
        ...(logo ? { attachments: [logo] } : {}),
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

    if (purpose === 'login') {
      void sendRiderWelcomeEmail(email);
    }

    return res.json({
      ok: true,
      email,
      purpose,
      verified: true,
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
    `CitiRide OTP API listening on :${port} (demoMode=${demoMode}, hasResendKey=${Boolean(resendApiKey)})`,
  );
});

async function sendRiderWelcomeEmail(email) {
  if (demoMode || !resend) {
    return;
  }

  if (welcomeSent.has(email)) {
    return;
  }

  welcomeSent.add(email);

  try {
    const logo = logoAttachment();
    const { error } = await resend.emails.send({
      from: fromEmail,
      to: [email],
      subject: 'Welcome to CitiRide',
      html: riderWelcomeEmailHtml({ email }),
      text: riderWelcomeEmailText({ email }),
      ...(logo ? { attachments: [logo] } : {}),
    });

    if (error) {
      welcomeSent.delete(email);
      console.error('welcome email failed', error);
    }
  } catch (error) {
    welcomeSent.delete(email);
    console.error('welcome email failed', error);
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
  if (['login', 'wallet', 'reset_pin'].includes(purpose)) {
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
