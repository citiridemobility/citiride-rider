import admin from 'firebase-admin';
import crypto from 'node:crypto';

import { initFirebaseAdmin } from './firebase-admin.js';

const PHOTO_BUCKET =
  process.env.FIREBASE_STORAGE_BUCKET?.trim().replace(/^gs:\/\//, '') ||
  'citiride-d7743-driver-photos';

const MAX_BYTES = 5 * 1024 * 1024;

function decodeImagePayload(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;

  const dataUrl = raw.match(/^data:([^;]+);base64,(.+)$/i);
  if (dataUrl) {
    return {
      contentType: dataUrl[1],
      buffer: Buffer.from(dataUrl[2], 'base64'),
    };
  }

  return {
    contentType: null,
    buffer: Buffer.from(raw, 'base64'),
  };
}

export async function handleDriverPhotoUpload(req, res) {
  if (!initFirebaseAdmin()) {
    return res.status(503).json({
      error: 'storage_unavailable',
      message: 'Photo upload is not available right now.',
    });
  }

  const header = String(req.headers.authorization || '');
  const idToken = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!idToken) {
    return res.status(401).json({
      error: 'missing_token',
      message: 'Sign in again, then upload your photo.',
    });
  }

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch {
    return res.status(401).json({
      error: 'invalid_token',
      message: 'Sign in again, then upload your photo.',
    });
  }

  const uid = String(decoded.uid || '').trim();
  const role = decoded.role || decoded.claims?.role;
  const isDriver = role === 'driver' || uid.startsWith('drv_');
  if (!uid || !isDriver) {
    return res.status(403).json({
      error: 'forbidden',
      message: 'Only signed-in drivers can upload a profile photo.',
    });
  }

  const parsed = decodeImagePayload(req.body?.imageBase64);
  const contentType = String(
    req.body?.contentType || parsed?.contentType || 'image/jpeg',
  ).toLowerCase();
  if (!parsed?.buffer?.length) {
    return res.status(400).json({
      error: 'missing_image',
      message: 'Choose a profile photo first.',
    });
  }
  if (!contentType.startsWith('image/')) {
    return res.status(400).json({
      error: 'invalid_type',
      message: 'Profile photos must be image files.',
    });
  }
  if (parsed.buffer.length > MAX_BYTES) {
    return res.status(413).json({
      error: 'too_large',
      message: 'Profile photos must be under 5MB.',
    });
  }

  const objectPath = `driver-photos/${uid}/profile.jpg`;
  const downloadToken = crypto.randomUUID();
  const file = admin.storage().bucket(PHOTO_BUCKET).file(objectPath);
  await file.save(parsed.buffer, {
    resumable: false,
    public: false,
    metadata: {
      contentType,
      cacheControl: 'public, max-age=3600',
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
  });

  let url = `https://firebasestorage.googleapis.com/v0/b/${PHOTO_BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media&token=${downloadToken}`;
  try {
    const [signed] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
      version: 'v4',
    });
    if (signed) {
      url = signed;
    }
  } catch (error) {
    console.warn('Driver photo signed URL skipped:', error?.message || error);
  }

  try {
    await admin.firestore().collection('drivers').doc(uid).set(
      {
        photoUri: url,
        photoURL: url,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    console.warn('Driver photo Firestore write skipped:', error?.message || error);
  }

  return res.json({ ok: true, url, driverId: uid });
}
