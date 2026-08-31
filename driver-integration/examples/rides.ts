/**
 * Example ride matching helpers for React Native.
 * Requires: @react-native-firebase/auth, @react-native-firebase/firestore
 */

import auth from '@react-native-firebase/auth';
import firestore from '@react-native-firebase/firestore';

import type { DriverLocation, RideDoc, RideStatus } from '../firestore.types';
import { COLLECTIONS } from '../firestore.types';

function requireDriverId(): string {
  const uid = auth().currentUser?.uid;
  if (!uid) {
    throw new Error('Driver must be signed in before matching rides.');
  }
  return uid;
}

/** Live list of open ride requests. */
export function watchRequestedRides(
  onChange: (rides: Array<RideDoc & { id: string }>) => void,
  onError?: (error: Error) => void,
) {
  return firestore()
    .collection(COLLECTIONS.rides)
    .where('status', '==', 'requested')
    .onSnapshot(
      (snap) => {
        const rides = snap.docs.map((doc) => ({
          id: doc.id,
          ...(doc.data() as RideDoc),
        }));
        onChange(rides);
      },
      (error) => onError?.(error as Error),
    );
}

/** Accept an open request. Auth UID becomes driverId. */
export async function acceptRide(rideId: string) {
  const driverId = requireDriverId();
  await firestore().collection(COLLECTIONS.rides).doc(rideId).update({
    status: 'accepted' satisfies RideStatus,
    driverId,
    updatedAt: firestore.FieldValue.serverTimestamp(),
  });
  return driverId;
}

export async function updateRideStatus(rideId: string, status: RideStatus) {
  requireDriverId();
  await firestore().collection(COLLECTIONS.rides).doc(rideId).update({
    status,
    updatedAt: firestore.FieldValue.serverTimestamp(),
  });
}

/** Preferred live GPS channel — rider listens to driverLocations/{driverId}. */
export async function publishDriverLocation(location: {
  lat: number;
  lng: number;
  heading: number;
}) {
  const driverId = requireDriverId();
  const payload: DriverLocation = {
    lat: location.lat,
    lng: location.lng,
    heading: location.heading,
    updatedAt: firestore.FieldValue.serverTimestamp(),
  };

  await firestore()
    .collection(COLLECTIONS.driverLocations)
    .doc(driverId)
    .set(payload, { merge: true });

  return driverId;
}

/** Optional: also mirror GPS onto the active ride doc. */
export async function mirrorLocationOntoRide(
  rideId: string,
  location: { lat: number; lng: number; heading: number },
) {
  requireDriverId();
  await firestore().collection(COLLECTIONS.rides).doc(rideId).update({
    driverLocation: {
      lat: location.lat,
      lng: location.lng,
      heading: location.heading,
      updatedAt: firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: firestore.FieldValue.serverTimestamp(),
  });
}

export function watchAssignedRide(
  rideId: string,
  onChange: (ride: (RideDoc & { id: string }) | null) => void,
  onError?: (error: Error) => void,
) {
  return firestore()
    .collection(COLLECTIONS.rides)
    .doc(rideId)
    .onSnapshot(
      (snap) => {
        if (!snap.exists) {
          onChange(null);
          return;
        }
        onChange({ id: snap.id, ...(snap.data() as RideDoc) });
      },
      (error) => onError?.(error as Error),
    );
}
