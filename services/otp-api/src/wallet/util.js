import crypto from 'node:crypto';

import admin from 'firebase-admin';

import { hasFirebaseAdmin, initFirebaseAdmin } from '../firebase-admin.js';

export function getFirestore() {
  if (!initFirebaseAdmin()) {
    throw new Error('Firebase Admin is not configured');
  }
  return admin.firestore();
}

export async function verifyBearerToken(authorizationHeader) {
  if (!hasFirebaseAdmin()) {
    return null;
  }
  const raw = String(authorizationHeader || '');
  const match = raw.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(match[1].trim());
    return {
      uid: decoded.uid,
      email: String(decoded.email || '').trim().toLowerCase(),
    };
  } catch {
    return null;
  }
}

export function newReference(prefix) {
  const stamp = Date.now().toString(36);
  const rand = crypto.randomBytes(4).toString('hex');
  return `${prefix}_${stamp}_${rand}`;
}

export function toKobo(nairaAmount) {
  return Math.round(Number(nairaAmount) * 100);
}

export function fromKobo(kobo) {
  return Number(kobo || 0) / 100;
}

/** Platform take rate. Override with CITIRIDE_COMMISSION_PERCENT (0–100). */
export function commissionPercent() {
  const n = Number(process.env.CITIRIDE_COMMISSION_PERCENT ?? 20);
  if (!Number.isFinite(n) || n < 0) return 20;
  return Math.min(100, n);
}

export function platformWalletId() {
  const id = String(process.env.CITIRIDE_PLATFORM_WALLET_ID || 'citiride_platform').trim();
  return id || 'citiride_platform';
}

export function splitFareKobo(fareKobo, percent = commissionPercent()) {
  const safeFare = Math.max(0, Math.round(Number(fareKobo) || 0));
  const rate = Math.min(100, Math.max(0, Number(percent) || 0));
  const commissionKobo = Math.round(safeFare * (rate / 100));
  const driverKobo = Math.max(0, safeFare - commissionKobo);
  return { fareKobo: safeFare, commissionKobo, driverKobo, percent: rate };
}
