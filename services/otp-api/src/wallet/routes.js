import express from 'express';

import {
  isTransferBank,
  mapPaystackBank,
} from '../paystack/bank-logos.js';
import {
  hasPaystack,
  isPaystackTestMode,
  listBanks,
  resolveAccountNumber,
  verifyPaystackSignature,
} from '../paystack/client.js';
import {
  confirmRideCashPayment,
  ensureFundingAccount,
  getOrCreateWallet,
  handleChargeSuccess,
  handleTransferEvent,
  listTransactions,
  payRideFare,
  requeryWalletFunding,
  requestWithdrawal,
  simulateTestDeposit,
} from './ledger.js';
import { verifyBearerToken } from './util.js';

export const walletRouter = express.Router();

async function requireAuth(req, res) {
  const auth = await verifyBearerToken(req.headers.authorization);
  if (auth?.uid) {
    return auth;
  }

  // Dev fallback when Firebase Admin/token is unavailable: explicit userId.
  // Never use this for production without additional shared-secret checks.
  const allowFallback =
    process.env.WALLET_ALLOW_USERID_FALLBACK === 'true' ||
    process.env.OTP_DEMO_MODE === 'true';
  const userId = String(req.headers['x-user-id'] || req.body?.userId || '').trim();
  if (allowFallback && userId) {
    return {
      uid: userId,
      email: String(req.body?.email || req.headers['x-user-email'] || ''),
    };
  }

  res.status(401).json({
    error: 'unauthorized',
    message: 'Sign in required to access wallet.',
  });
  return null;
}

walletRouter.get('/status', (_req, res) => {
  res.json({
    ok: true,
    paystackConfigured: hasPaystack(),
    testMode: isPaystackTestMode(),
  });
});

walletRouter.post('/ensure', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const email = String(req.body?.email || auth.email || '')
      .trim()
      .toLowerCase();
    const fullName = String(req.body?.fullName || '').trim();
    const phone = String(req.body?.phone || '').trim();

    const wallet = await ensureFundingAccount(auth.uid, {
      email,
      fullName,
      phone,
    });

    return res.json({ ok: true, wallet });
  } catch (error) {
    console.error('wallet ensure failed', error);
    return res.status(400).json({
      error: 'wallet_ensure_failed',
      message: error.message || 'Unable to prepare funding account',
    });
  }
});

walletRouter.get('/me', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const wallet = await getOrCreateWallet(auth.uid, {
      email: auth.email,
    });
    return res.json({ ok: true, wallet });
  } catch (error) {
    console.error('wallet me failed', error);
    return res.status(500).json({
      error: 'wallet_fetch_failed',
      message: error.message || 'Unable to load wallet',
    });
  }
});

walletRouter.get('/me/transactions', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;
    const limit = Number(req.query.limit || 30);
    const transactions = await listTransactions(auth.uid, { limit });
    return res.json({ ok: true, transactions });
  } catch (error) {
    console.error('wallet transactions failed', error);
    return res.status(500).json({
      error: 'wallet_transactions_failed',
      message: error.message || 'Unable to load transactions',
    });
  }
});

const BANKS_CACHE_MS = 12 * 60 * 60 * 1000;
let banksCache = { at: 0, banks: null };

walletRouter.get('/banks', async (_req, res) => {
  try {
    if (banksCache.banks && Date.now() - banksCache.at < BANKS_CACHE_MS) {
      return res.json({ ok: true, banks: banksCache.banks });
    }

    const result = await listBanks();
    const seen = new Set();
    const banks = (result.data || [])
      .filter(isTransferBank)
      .map(mapPaystackBank)
      .filter((bank) => {
        if (seen.has(bank.code)) return false;
        seen.add(bank.code);
        return true;
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    banksCache = { at: Date.now(), banks };
    return res.json({ ok: true, banks });
  } catch (error) {
    console.error('wallet banks failed', error);
    return res.status(400).json({
      error: 'banks_failed',
      message: error.message || 'Unable to load banks',
    });
  }
});

walletRouter.post('/bank/resolve', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const accountNumber = String(req.body?.accountNumber || '').trim();
    const bankCode = String(req.body?.bankCode || '').trim();
    if (!/^\d{10}$/.test(accountNumber) || !bankCode) {
      return res.status(400).json({
        error: 'invalid_account',
        message: 'Enter a valid 10-digit account number and bank.',
      });
    }

    const result = await resolveAccountNumber({ accountNumber, bankCode });
    const accountName = String(result.data?.account_name || '').trim();
    if (!accountName) {
      return res.status(400).json({
        error: 'resolve_failed',
        message:
          'Account name not found. Confirm the bank and 10-digit account number.',
      });
    }
    return res.json({
      ok: true,
      accountNumber,
      bankCode,
      accountName,
    });
  } catch (error) {
    console.error('wallet bank resolve failed', error);
    const paystackMessage = String(error.message || '').trim();
    return res.status(400).json({
      error: 'resolve_failed',
      message:
        paystackMessage ||
        'Unable to resolve account. Confirm bank and account number.',
    });
  }
});

walletRouter.post('/funding/requery', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const wallet = await requeryWalletFunding(auth.uid);
    return res.json({
      ok: true,
      wallet,
      message: 'Wallet updated from Paystack.',
    });
  } catch (error) {
    console.error('wallet funding requery failed', error);
    return res.status(400).json({
      error: 'funding_requery_failed',
      message: error.message || 'Unable to requery funding account',
    });
  }
});

walletRouter.post('/test/credit', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const amount = Number(req.body?.amount ?? 1000);
    const wallet = await simulateTestDeposit(auth.uid, amount);
    return res.json({ ok: true, wallet });
  } catch (error) {
    console.error('wallet test credit failed', error);
    return res.status(400).json({
      error: 'test_credit_failed',
      message: error.message || 'Unable to simulate test deposit',
    });
  }
});

walletRouter.post('/ride/pay', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const rideId = String(req.body?.rideId || '').trim();
    if (!rideId) {
      return res.status(400).json({
        error: 'invalid_ride',
        message: 'Ride id is required.',
      });
    }

    const result = await payRideFare({
      riderId: auth.uid,
      rideId,
    });
    return res.json({ ok: true, ...result });
  } catch (error) {
    console.error('wallet ride pay failed', error);
    const code = error.code || 'ride_pay_failed';
    const status =
      code === 'not_found' ? 404 : code === 'forbidden' ? 403 : 400;
    return res.status(status).json({
      error: code === 'insufficient_funds' ? 'insufficient_funds' : code,
      message: error.message || 'Unable to pay for this ride',
    });
  }
});

walletRouter.post('/ride/confirm-cash', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const rideId = String(req.body?.rideId || '').trim();
    if (!rideId) {
      return res.status(400).json({
        error: 'invalid_ride',
        message: 'Ride id is required.',
      });
    }

    const result = await confirmRideCashPayment({
      riderId: auth.uid,
      rideId,
    });
    return res.json({ ok: true, ...result });
  } catch (error) {
    console.error('wallet ride cash confirm failed', error);
    const code = error.code || 'ride_cash_failed';
    const status =
      code === 'not_found' ? 404 : code === 'forbidden' ? 403 : 400;
    return res.status(status).json({
      error: code,
      message: error.message || 'Unable to confirm cash payment',
    });
  }
});

walletRouter.post('/withdraw', async (req, res) => {
  try {
    const auth = await requireAuth(req, res);
    if (!auth) return;

    const amount = Number(req.body?.amount);
    const bankCode = String(req.body?.bankCode || '').trim();
    const bankName = String(req.body?.bankName || '').trim();
    const accountNumber = String(req.body?.accountNumber || '').trim();
    const accountName = String(req.body?.accountName || '').trim();

    if (!Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({
        error: 'invalid_amount',
        message: 'Enter a valid withdrawal amount.',
      });
    }
    if (!/^\d{10}$/.test(accountNumber) || !bankCode) {
      return res.status(400).json({
        error: 'invalid_account',
        message: 'Enter a valid bank account.',
      });
    }

    const result = await requestWithdrawal({
      userId: auth.uid,
      amountNaira: amount,
      bankCode,
      bankName,
      accountNumber,
      accountName,
    });

    return res.json({ ok: true, withdrawal: result });
  } catch (error) {
    console.error('wallet withdraw failed', error);
    return res.status(400).json({
      error: 'withdraw_failed',
      message: error.message || 'Unable to start withdrawal',
    });
  }
});

/**
 * Paystack webhook — must receive raw body for signature verification.
 * Mounted separately in index.js with express.raw.
 */
export async function handlePaystackWebhook(req, res) {
  try {
    const signature = req.headers['x-paystack-signature'];
    const rawBody = Buffer.isBuffer(req.body)
      ? req.body
      : Buffer.from(typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {}));

    if (!verifyPaystackSignature(rawBody, signature)) {
      return res.status(401).json({ error: 'invalid_signature' });
    }

    const event = JSON.parse(rawBody.toString('utf8'));
    const eventName = String(event.event || '');

    if (eventName === 'charge.success') {
      const result = await handleChargeSuccess(event);
      return res.json({ ok: true, handled: 'charge.success', result });
    }

    if (
      eventName === 'transfer.success' ||
      eventName === 'transfer.failed' ||
      eventName === 'transfer.reversed'
    ) {
      const result = await handleTransferEvent(eventName, event);
      return res.json({ ok: true, handled: eventName, result });
    }

    return res.json({ ok: true, ignored: eventName });
  } catch (error) {
    console.error('paystack webhook failed', error);
    return res.status(500).json({
      error: 'webhook_failed',
      message: error.message || 'Unable to process webhook',
    });
  }
}
