import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/firebase/firestore_paths.dart';
import '../domain/live_ride.dart';

/// Firestore access for live ride request / matching.
///
/// Matching v1 (shared with driver app):
/// 1. Rider creates `rides/{id}` with `status: requested`, `driverId: null`.
/// 2. Driver app lists/listens for nearby `requested` rides and accepts.
/// 3. On accept, driver sets `driverId` + `status: accepted`.
/// 4. Rider [watchRide] sees the update and continues the trip UI.
class RideRepository {
  RideRepository({this._firestore});

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db {
    final injected = _firestore;
    if (injected != null) {
      return injected;
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    return FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> get _rides {
    return _db.collection(FirestoreCollections.rides);
  }

  /// Creates a ride request open for drivers to accept.
  Future<LiveRide> requestRide(NewRideRequest request) async {
    final doc = _rides.doc();
    await doc.set(newRideWriteMap(request));
    final snap = await doc.get();
    final data = snap.data();
    if (data == null) {
      return LiveRide(
        id: doc.id,
        riderId: request.riderId,
        status: RideStatus.requested,
        pickup: request.pickup,
        destination: request.destination,
        fare: RideFare(estimated: request.estimatedFare),
        rideType: request.rideType,
        paymentMethod: request.paymentMethod,
      );
    }
    return LiveRide.fromMap(snap.id, data);
  }

  Stream<LiveRide> watchRide(String rideId) {
    return _rides.doc(rideId).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) {
        throw StateError('Ride $rideId was deleted.');
      }
      try {
        return LiveRide.fromMap(snap.id, data);
      } on Object catch (error, stackTrace) {
        debugPrint('Failed to parse ride $rideId: $error');
        debugPrintStack(stackTrace: stackTrace);
        rethrow;
      }
    });
  }

  Future<void> cancelRide(String rideId) {
    return _rides
        .doc(rideId)
        .update(rideStatusUpdateMap(RideStatus.cancelled));
  }

  /// Live driver GPS. Driver app should write:
  /// `driverLocations/{driverId}` → `{ lat, lng, heading, updatedAt }`.
  /// Prefer also mirroring onto the ride as `driverLocation` for one-stream UIs.
  Stream<DriverLocation> watchDriverLocation(String driverId) {
    return _db
        .collection(FirestoreCollections.driverLocations)
        .doc(driverId)
        .snapshots()
        .where((snap) => snap.exists && snap.data() != null)
        .map((snap) => DriverLocation.fromMap(snap.data()!));
  }

  /// Live driver profile for the rider trip card (name / vehicle / photo).
  Stream<DriverProfileSummary> watchDriverProfile(String driverId) {
    return _db
        .collection(FirestoreCollections.drivers)
        .doc(driverId)
        .snapshots()
        .where((snap) => snap.exists && snap.data() != null)
        .map((snap) => DriverProfileSummary.fromMap(snap.id, snap.data()!));
  }

  /// Nearby, recently-updated online drivers from the `drivers` collection.
  ///
  /// The driver app writes its real device position here while online. The
  /// radius check happens client-side for now because the matching collection
  /// is not yet queried with a geohash range. Never return a driver's last
  /// known position after its location heartbeat has gone stale.
  Stream<List<NearbyDriver>> watchNearbyDrivers({
    required LatLng center,
    double radiusMeters = 5000,
    int limit = 24,
    Duration maximumLocationAge = const Duration(minutes: 2),
  }) {
    return _db
        .collection(FirestoreCollections.drivers)
        .where('status', isEqualTo: 'online')
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          final nearby = snap.docs
              .map((doc) => NearbyDriver.fromMap(doc.id, doc.data()))
              .where((driver) {
                final updatedAt = driver.updatedAt?.toDate();
                return driver.lat != 0 &&
                    driver.lng != 0 &&
                    updatedAt != null &&
                    now.difference(updatedAt) <= maximumLocationAge &&
                    _distanceMeters(center, LatLng(driver.lat, driver.lng)) <=
                        radiusMeters;
              })
              .toList()
            ..sort(
              (first, second) => _distanceMeters(
                center,
                LatLng(first.lat, first.lng),
              ).compareTo(
                _distanceMeters(center, LatLng(second.lat, second.lng))),
            );
          return nearby.take(limit).toList(growable: false);
        });
  }

  static double _distanceMeters(LatLng first, LatLng second) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(first.latitude);
    final lat2 = _radians(second.latitude);
    final deltaLat = _radians(second.latitude - first.latitude);
    final deltaLng = _radians(second.longitude - first.longitude);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// Open requests for this rider (useful if app restarts mid-search).
  Stream<List<LiveRide>> watchOpenRequestsForRider(String riderId) {
    return _rides
        .where(FirestoreFields.riderId, isEqualTo: riderId)
        .where(FirestoreFields.status, isEqualTo: RideStatus.requested.toFirestore())
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => LiveRide.fromMap(doc.id, doc.data()))
              .toList(growable: false);
        });
  }
}
