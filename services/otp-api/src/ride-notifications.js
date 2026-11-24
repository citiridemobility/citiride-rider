import express from 'express';

import { admin, hasFirebaseAdmin } from './firebase-admin.js';
import { getFirestore, verifyBearerToken } from './wallet/util.js';

export const rideNotificationsRouter = express.Router();

async function requireAuth(req, res) {
  const auth = await verifyBearerToken(req.headers.authorization);
  if (!auth?.uid) {
    res.status(401).json({ error: 'unauthorized', message: 'Sign in required.' });
    return null;
  }
  return auth;
}

function text(value, fallback = '') {
  const clean = String(value || '').trim();
  return clean || fallback;
}

async function sendExpoNotifications(tokens, message) {
  if (!tokens.length) return 0;
  const payload = tokens.map((to) => ({
    to,
    sound: 'default',
    priority: 'high',
    channelId: 'incoming-ride',
    title: message.title,
    body: message.body,
    data: message.data,
  }));

  try {
    const response = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Accept-encoding': 'gzip, deflate',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      console.warn('Expo ride notification rejected:', response.status);
      return 0;
    }
    return tokens.length;
  } catch (error) {
    console.warn('Expo ride notification failed:', error?.message || error);
    return 0;
  }
}

/** Rider event: notify the drivers currently eligible for ride requests. */
rideNotificationsRouter.post('/ride-request', async (req, res) => {
  const auth = await requireAuth(req, res);
  if (!auth) return;
  if (!hasFirebaseAdmin()) {
    return res.status(503).json({ error: 'unavailable' });
  }

  const rideId = text(req.body?.rideId);
  if (!rideId) {
    return res.status(400).json({ error: 'invalid_ride' });
  }

  try {
    const db = getFirestore();
    const rideSnap = await db.collection('rides').doc(rideId).get();
    const ride = rideSnap.data();
    if (!rideSnap.exists || text(ride?.riderId) !== auth.uid) {
      return res.status(403).json({ error: 'forbidden' });
    }

    const pickup = text(ride?.pickup?.address, 'the pickup location');
    const onlineDrivers = await db
      .collection('drivers')
      .where('status', '==', 'online')
      .limit(32)
      .get();
    const tokens = onlineDrivers.docs
      .map((driver) => text(driver.data().expoPushToken))
      .filter((token) => token.startsWith('ExponentPushToken['));
    const sent = await sendExpoNotifications(tokens, {
      title: 'New ride request',
      body: `Pickup: ${pickup}`,
      data: { kind: 'incoming-ride', rideId },
    });
    return res.json({ ok: true, sent });
  } catch (error) {
    console.error('ride-request notification failed:', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

/** Driver event: let the assigned rider know who accepted their ride. */
rideNotificationsRouter.post('/ride-accepted', async (req, res) => {
  const auth = await requireAuth(req, res);
  if (!auth) return;
  if (!hasFirebaseAdmin()) {
    return res.status(503).json({ error: 'unavailable' });
  }

  const rideId = text(req.body?.rideId);
  if (!rideId) {
    return res.status(400).json({ error: 'invalid_ride' });
  }

  try {
    const db = getFirestore();
    const rideSnap = await db.collection('rides').doc(rideId).get();
    const ride = rideSnap.data();
    if (!rideSnap.exists || text(ride?.driverId) !== auth.uid) {
      return res.status(403).json({ error: 'forbidden' });
    }

    const riderId = text(ride?.riderId);
    const riderSnap = riderId
      ? await db.collection('riders').doc(riderId).get()
      : null;
    const token = text(riderSnap?.data()?.fcmToken);
    if (!token) {
      return res.json({ ok: true, sent: false });
    }

    const driverName = text(ride?.driverName, 'Your driver');
    await admin.messaging().send({
      token,
      notification: {
        title: 'Driver accepted your ride',
        body: `${driverName} is driving to your pickup location.`,
      },
      data: { kind: 'ride-accepted', rideId },
      android: {
        priority: 'high',
        notification: { sound: 'default', channelId: 'ride-updates' },
      },
      apns: {
        payload: { aps: { sound: 'default' } },
      },
    });
    return res.json({ ok: true, sent: true });
  } catch (error) {
    console.error('ride-accepted notification failed:', error);
    return res.status(500).json({ error: 'server_error' });
  }
});
