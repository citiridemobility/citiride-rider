import admin from 'firebase-admin';

let initialized = false;
let initError = null;

/**
 * Initialize Firebase Admin from env.
 * Prefer FIREBASE_SERVICE_ACCOUNT_JSON (full service-account JSON string).
 * Falls back to Application Default Credentials / GOOGLE_APPLICATION_CREDENTIALS.
 */
export function initFirebaseAdmin() {
  if (initialized) {
    return true;
  }
  if (initError) {
    return false;
  }

  try {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    if (raw) {
      const parsed = JSON.parse(raw);
      admin.initializeApp({
        credential: admin.credential.cert(parsed),
        projectId: parsed.project_id || process.env.FIREBASE_PROJECT_ID,
      });
      initialized = true;
      return true;
    }

    const projectId = process.env.FIREBASE_PROJECT_ID?.trim() || 'citiride-d7743';
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
    initialized = true;
    return true;
  } catch (error) {
    initError = error;
    console.warn('Firebase Admin not initialized:', error?.message || error);
    return false;
  }
}

export function hasFirebaseAdmin() {
  return initFirebaseAdmin();
}

/** Stable Firebase Auth uid for a rider email (matches Flutter riderIdFromEmail). */
export function riderUidFromEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9@._+-]/g, '_');
}

/**
 * Mint a Firebase custom token after email OTP succeeds.
 * @returns {Promise<string|null>}
 */
export async function createRiderCustomToken(email) {
  if (!initFirebaseAdmin()) {
    return null;
  }

  const uid = riderUidFromEmail(email);
  if (!uid) {
    return null;
  }

  return admin.auth().createCustomToken(uid, {
    email,
    riderId: uid,
    role: 'rider',
  });
}
