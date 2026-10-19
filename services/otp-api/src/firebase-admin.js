import admin from 'firebase-admin';

export { admin };

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
        storageBucket:
          process.env.FIREBASE_STORAGE_BUCKET?.trim().replace(/^gs:\/\//, '') ||
          'citiride-d7743-driver-photos',
      });
      initialized = true;
      return true;
    }

    const projectId = process.env.FIREBASE_PROJECT_ID?.trim() || 'citiride-d7743';
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
      storageBucket:
        process.env.FIREBASE_STORAGE_BUCKET?.trim().replace(/^gs:\/\//, '') ||
        'citiride-d7743-driver-photos',
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
 * Stable Firebase Auth uid for a driver email.
 * Prefixed so the same person can hold separate rider + driver Auth accounts.
 * Firebase custom-token UIDs may only contain [A-Za-z0-9._-].
 */
export function driverUidFromEmail(email) {
  const safe = String(email || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, '_');
  return safe ? `drv_${safe}` : '';
}

/**
 * Ensure the Auth user exists with a real email so client SDKs expose user.email.
 */
async function ensureAuthUserWithEmail(uid, email) {
  const normalized = String(email || '')
    .trim()
    .toLowerCase();
  if (!uid || !normalized) return;

  try {
    await admin.auth().updateUser(uid, {
      email: normalized,
      emailVerified: true,
    });
  } catch (error) {
    if (error?.code === 'auth/user-not-found') {
      await admin.auth().createUser({
        uid,
        email: normalized,
        emailVerified: true,
      });
      return;
    }
    // Email already used on another uid — keep token minting working.
    console.warn('ensureAuthUserWithEmail failed:', error?.code || error);
  }
}

/**
 * Mint a Firebase custom token after rider email OTP succeeds.
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

  await ensureAuthUserWithEmail(uid, email);

  return admin.auth().createCustomToken(uid, {
    email,
    riderId: uid,
    role: 'rider',
  });
}

/**
 * Mint a Firebase custom token after driver email OTP succeeds.
 * @returns {Promise<{ token: string, uid: string }|null>}
 */
export async function createDriverCustomToken(email) {
  if (!initFirebaseAdmin()) {
    return null;
  }

  const uid = driverUidFromEmail(email);
  if (!uid) {
    return null;
  }

  await ensureAuthUserWithEmail(uid, email);

  const token = await admin.auth().createCustomToken(uid, {
    email,
    driverId: uid,
    role: 'driver',
  });

  return { token, uid };
}

async function authUserExists(uid) {
  if (!uid || !initFirebaseAdmin()) return false;
  try {
    await admin.auth().getUser(uid);
    return true;
  } catch (error) {
    if (error?.code === 'auth/user-not-found') return false;
    console.warn('authUserExists failed:', error?.code || error);
    return false;
  }
}

async function firestoreDocExists(collection, uid) {
  if (!uid || !initFirebaseAdmin()) return false;
  try {
    const snap = await admin.firestore().collection(collection).doc(uid).get();
    return snap.exists;
  } catch (error) {
    console.warn('firestoreDocExists failed:', error?.message || error);
    return false;
  }
}

async function authEmailMatchesRole(email, role) {
  if (!initFirebaseAdmin()) return false;
  try {
    const user = await admin.auth().getUserByEmail(email);
    const claimsRole = user.customClaims?.role;
    if (role === 'driver') {
      return (
        claimsRole === 'driver' || String(user.uid || '').startsWith('drv_')
      );
    }
    return (
      claimsRole === 'rider' || !String(user.uid || '').startsWith('drv_')
    );
  } catch (error) {
    if (error?.code === 'auth/user-not-found') return false;
    console.warn('authEmailMatchesRole failed:', error?.code || error);
    return false;
  }
}

async function firestoreEmailExists(collection, email) {
  if (!email || !initFirebaseAdmin()) return false;
  try {
    const snap = await admin
      .firestore()
      .collection(collection)
      .where('email', '==', email)
      .limit(1)
      .get();
    return !snap.empty;
  } catch (error) {
    console.warn('firestoreEmailExists failed:', error?.message || error);
    return false;
  }
}

export async function riderAccountExists(email) {
  const uid = riderUidFromEmail(email);
  if (!uid) return false;
  if (await authUserExists(uid)) return true;
  if (await firestoreDocExists('riders', uid)) return true;
  if (await authEmailMatchesRole(email, 'rider')) return true;
  return firestoreEmailExists('riders', email);
}

export async function driverAccountExists(email) {
  const uid = driverUidFromEmail(email);
  if (!uid) return false;
  if (await authUserExists(uid)) return true;
  if (await firestoreDocExists('drivers', uid)) return true;
  if (await authEmailMatchesRole(email, 'driver')) return true;
  return firestoreEmailExists('drivers', email);
}

