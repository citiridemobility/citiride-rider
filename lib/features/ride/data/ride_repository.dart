import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
