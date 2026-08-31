/**
 * Shared Firestore contract for CitiRide rider (Flutter) ↔ driver (React Native).
 * Copy into the driver app as needed.
 */

export type RideStatus =
  | 'requested'
  | 'accepted'
  | 'arriving'
  | 'waiting'
  | 'in_progress'
  | 'confirm_fare'
  | 'completed'
  | 'cancelled';

export type RideType = 'regular' | 'vip';
export type PaymentMethod = 'cash' | 'wallet';

export interface RideLatLng {
  lat: number;
  lng: number;
  address: string;
}

export interface RideFare {
  estimated: number;
  final: number | null;
}

export interface DriverLocation {
  lat: number;
  lng: number;
  /** Degrees clockwise from north. */
  heading: number;
  updatedAt?: unknown; // Firestore Timestamp
}

export interface RideDoc {
  riderId: string;
  driverId: string | null;
  status: RideStatus;
  pickup: RideLatLng;
  destination: RideLatLng;
  fare: RideFare;
  rideType: RideType;
  paymentMethod: PaymentMethod;
  driverLocation?: DriverLocation | null;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface DriverProfileDoc {
  email: string;
  driverId: string;
  authProvider: 'email_otp';
  role: 'driver';
  displayName?: string;
  phone?: string;
  updatedAt?: unknown;
}

export const COLLECTIONS = {
  rides: 'rides',
  drivers: 'drivers',
  driverLocations: 'driverLocations',
  riders: 'riders',
} as const;

/** Mirrors otp-api `driverUidFromEmail`. */
export function driverUidFromEmail(email: string): string {
  const base = email
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9@._+-]/g, '_');
  return base ? `drv_${base}` : '';
}
