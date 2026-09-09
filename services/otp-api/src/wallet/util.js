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
