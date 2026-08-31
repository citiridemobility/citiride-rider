/**
 * Example driver auth helpers for React Native.
 * Requires: @react-native-firebase/auth, @react-native-firebase/firestore
 *
 * Adapt imports / fetch client to your project.
 */

import auth from '@react-native-firebase/auth';
import firestore from '@react-native-firebase/firestore';

export const OTP_API_BASE =
  'https://otp-api-production-db79.up.railway.app';

export type DriverOtpSendResult = {
  ok: true;
  email: string;
  purpose: 'driver_login';
  role: 'driver';
  expiresInMs: number;
  demoMode: boolean;
  demoCode?: string;
};

export type DriverOtpVerifyResult = {
  ok: true;
  email: string;
  purpose: 'driver_login';
  role: 'driver';
  verified: true;
  driverId: string | null;
  firebaseCustomToken?: string;
};

async function postJson<T>(path: string, body: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${OTP_API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = (await res.json()) as T & { message?: string; error?: string };
  if (!res.ok) {
    throw new Error(data.message || data.error || `HTTP ${res.status}`);
  }
  return data;
}

export function sendDriverOtp(email: string) {
  return postJson<DriverOtpSendResult>('/v1/driver/otp/send', { email });
}

export function verifyDriverOtp(email: string, code: string) {
  return postJson<DriverOtpVerifyResult>('/v1/driver/otp/verify', {
    email,
    code,
  });
}

/** Full login: verify OTP → Firebase Auth → upsert drivers/{uid}. */
export async function loginDriverWithEmailOtp(email: string, code: string) {
  const verified = await verifyDriverOtp(email, code);
  const token = verified.firebaseCustomToken?.trim();
  if (!token) {
    throw new Error(
      'No firebaseCustomToken — OTP API Firebase Admin is not configured.',
    );
  }
  if (!verified.driverId) {
    throw new Error('No driverId in verify response.');
  }

  const credential = await auth().signInWithCustomToken(token);
  const uid = credential.user.uid;
  if (uid !== verified.driverId) {
    throw new Error(`Auth UID mismatch: ${uid} vs ${verified.driverId}`);
  }

  await firestore().collection('drivers').doc(uid).set(
    {
      email: email.trim().toLowerCase(),
      driverId: uid,
      authProvider: 'email_otp',
      role: 'driver',
      updatedAt: firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { uid, email: verified.email };
}

export function getSignedInDriverId(): string | null {
  return auth().currentUser?.uid ?? null;
}

export async function logoutDriver() {
  await auth().signOut();
}
