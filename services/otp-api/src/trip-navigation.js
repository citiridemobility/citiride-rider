import express from 'express';

import { getFirestore, verifyBearerToken } from './wallet/util.js';

export const tripNavigationRouter = express.Router();

const activeStatuses = new Set([
  'accepted',
  'arriving',
  'waiting',
  'in_progress',
]);
const pickupStatuses = new Set(['accepted', 'arriving']);

tripNavigationRouter.post('/route', async (req, res) => {
  try {
    const auth = await requireAuth(req);
    if (!auth) {
      return res.status(401).json({
        error: 'unauthorized',
        message: 'Sign in required to load trip navigation.',
      });
    }

    const rideId = String(req.body?.rideId || '').trim();
    if (!rideId) {
      return res.status(400).json({
        error: 'invalid_ride',
        message: 'Ride id is required.',
      });
    }

    const snapshot = await getFirestore().collection('rides').doc(rideId).get();
    if (!snapshot.exists) {
      return res.status(404).json({
        error: 'not_found',
        message: 'Ride not found.',
      });
    }

    const ride = snapshot.data() || {};
    if (String(ride.riderId || '') !== auth.uid) {
      return res.status(403).json({
        error: 'forbidden',
        message: 'You cannot view navigation for this ride.',
      });
    }

    const status = String(ride.status || 'requested');
    if (!activeStatuses.has(status)) {
      return res.status(409).json({
        error: 'trip_not_active',
        message: 'Live navigation is only available during an active ride.',
      });
    }

    const driver = parseLocation(ride.driverLocation);
    const target = parseLocation(
      pickupStatuses.has(status) ? ride.pickup : ride.destination,
    );
    const phase = pickupStatuses.has(status) ? 'to_pickup' : 'to_destination';

    if (!target) {
      return res.status(409).json({
        error: 'missing_route_target',
        message: 'This ride does not have a valid route target.',
      });
    }

    // An assigned driver may take a few seconds to publish their first fix.
    // Keep the screen live without inventing a mock car location.
    if (!driver) {
      return res.json({
        ok: true,
        phase,
        target,
        driverLocation: null,
        route: null,
      });
    }

    const route = await computeRoute(driver, target);
    return res.json({ ok: true, phase, target, driverLocation: driver, route });
  } catch (error) {
    console.error('trip navigation route failed', error);
    return res.status(500).json({
      error: 'navigation_failed',
      message: 'Unable to load live navigation. Please try again.',
    });
  }
});

async function requireAuth(req) {
  const verified = await verifyBearerToken(req.headers.authorization);
  if (verified?.uid) return verified;

  // Local-development fallback only. Production calls require an ID token.
  const allowFallback =
    process.env.OTP_DEMO_MODE === 'true' ||
    process.env.WALLET_ALLOW_USERID_FALLBACK === 'true';
  const uid = String(req.headers['x-user-id'] || req.body?.userId || '').trim();
  return allowFallback && uid ? { uid } : null;
}

function parseLocation(value) {
  if (!value || typeof value !== 'object') return null;
  const raw = value;
  const lat = Number(raw.lat ?? raw.latitude);
  const lng = Number(raw.lng ?? raw.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

  return {
    lat,
    lng,
    heading: normalizeHeading(Number(raw.heading ?? 0)),
    updatedAt: timestampToMillis(raw.updatedAt) || Date.now(),
    ...(Number.isFinite(Number(raw.sequence))
      ? { sequence: Number(raw.sequence) }
      : {}),
  };
}

function timestampToMillis(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  return 0;
}

function normalizeHeading(value) {
  if (!Number.isFinite(value)) return 0;
  return ((value % 360) + 360) % 360;
}

async function computeRoute(origin, destination) {
  const apiKey = String(
    process.env.GOOGLE_ROUTES_API_KEY ||
      process.env.GOOGLE_MAPS_SERVER_API_KEY ||
      '',
  ).trim();
  if (!apiKey) return null;

  const abort = new AbortController();
  const timeout = setTimeout(() => abort.abort(), 9000);
  try {
    const response = await fetch(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      {
        method: 'POST',
        signal: abort.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
            'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        },
        body: JSON.stringify({
          origin: waypoint(origin),
          destination: waypoint(destination),
          travelMode: 'DRIVE',
          routingPreference: 'TRAFFIC_AWARE',
          polylineQuality: 'HIGH_QUALITY',
          polylineEncoding: 'ENCODED_POLYLINE',
          regionCode: 'NG',
          units: 'METRIC',
        }),
      },
    );
    if (!response.ok) {
      console.warn('Routes API rejected live route:', response.status);
      return null;
    }

    const payload = await response.json();
    const route = Array.isArray(payload.routes) ? payload.routes[0] : null;
    const encodedPolyline = String(route?.polyline?.encodedPolyline || '');
    if (!route || !encodedPolyline) return null;

    return {
      encodedPolyline,
      distanceMeters: Number(route.distanceMeters) || 0,
      durationSeconds: durationSeconds(route.duration),
    };
  } finally {
    clearTimeout(timeout);
  }
}

function waypoint(point) {
  return {
    location: {
      latLng: { latitude: point.lat, longitude: point.lng },
    },
  };
}

function durationSeconds(value) {
  const seconds = Number(String(value || '').replace(/s$/, ''));
  return Number.isFinite(seconds) ? Math.max(0, Math.round(seconds)) : 0;
}
