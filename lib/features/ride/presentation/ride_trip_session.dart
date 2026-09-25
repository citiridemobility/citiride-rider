import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/ride_repository.dart';
import '../domain/live_ride.dart';

/// Snapshot of the active trip for map + screen routing.
class RideTripSnapshot {
  const RideTripSnapshot({
    required this.ride,
    this.driverLocation,
    this.driverProfile,
  });

  final LiveRide ride;
  final DriverLocation? driverLocation;
  final DriverProfileSummary? driverProfile;

  LatLng? get driverLatLng {
    final live = driverLocation;
    if (live != null) {
      return LatLng(live.lat, live.lng);
    }
    final fromRide = ride.driverLocation;
    if (fromRide != null) {
      return LatLng(fromRide.lat, fromRide.lng);
    }
    return null;
  }

  double? get driverHeading {
    return driverLocation?.heading ?? ride.driverLocation?.heading;
  }

  /// Prefer the live `drivers/{id}` profile for the current [ride.driverId]
  /// so a previous driver's name never sticks after reassignment.
  String get driverName {
    final fromProfile = driverProfile?.displayName?.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) {
      return fromProfile;
    }
    final fromRide = ride.driverName?.trim();
    if (fromRide != null && fromRide.isNotEmpty) {
      return fromRide;
    }
    return 'Driver';
  }

  String? get driverImage {
    final candidates = [driverProfile?.photoUri, ride.driverImage];
    for (final value in candidates) {
      final clean = value?.trim();
      if (clean != null &&
          (clean.startsWith('http://') || clean.startsWith('https://'))) {
        return clean;
      }
    }
    return null;
  }

  String? get driverVehicle {
    final fromProfile = driverProfile?.vehicleLabel?.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) {
      return fromProfile;
    }
    return ride.driverVehicle;
  }

  String? get driverPlate {
    final fromProfile = driverProfile?.plateNumber?.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) {
      return fromProfile;
    }
    return ride.driverPlate;
  }
}

/// Watches a ride doc (+ optional driverLocations/{driverId}) for the trip UI.
class RideTripSession {
  RideTripSession({
    required this.rideId,
    RideRepository? repository,
  }) : _repository = repository ?? RideRepository();

  final String rideId;
  final RideRepository _repository;

  StreamSubscription<LiveRide>? _rideSub;
  StreamSubscription<DriverLocation>? _locationSub;
  StreamSubscription<DriverProfileSummary>? _profileSub;
  String? _watchingDriverId;
  RideTripSnapshot? _latest;
  final _controller = StreamController<RideTripSnapshot>.broadcast();

  Stream<RideTripSnapshot> get snapshots => _controller.stream;
  RideTripSnapshot? get latest => _latest;

  void start() {
    _rideSub?.cancel();
    _rideSub = _repository.watchRide(rideId).listen(
      (ride) {
        final sameDriver =
            ride.driverId != null &&
            ride.driverId!.trim().isNotEmpty &&
            ride.driverId == _watchingDriverId;
        _latest = RideTripSnapshot(
          ride: ride,
          driverLocation: sameDriver ? _latest?.driverLocation : null,
          driverProfile: sameDriver ? _latest?.driverProfile : null,
        );
        _controller.add(_latest!);
        _syncDriverWatches(ride.driverId);
      },
      onError: _controller.addError,
    );
  }

  void _syncDriverWatches(String? driverId) {
    final clean = driverId?.trim();
    if (clean == null || clean.isEmpty) {
      unawaited(_locationSub?.cancel() ?? Future<void>.value());
      unawaited(_profileSub?.cancel() ?? Future<void>.value());
      _locationSub = null;
      _profileSub = null;
      _watchingDriverId = null;
      return;
    }
    if (clean == _watchingDriverId) {
      return;
    }
    _watchingDriverId = clean;
    unawaited(_locationSub?.cancel() ?? Future<void>.value());
    unawaited(_profileSub?.cancel() ?? Future<void>.value());

    _locationSub = _repository.watchDriverLocation(clean).listen(
      (location) {
        final ride = _latest?.ride;
        if (ride == null || ride.driverId != clean) {
          return;
        }
        _latest = RideTripSnapshot(
          ride: ride,
          driverLocation: location,
          driverProfile: _latest?.driverProfile,
        );
        _controller.add(_latest!);
      },
      onError: (_) {
        // Driver location is optional; ride status still drives the UI.
      },
    );

    _profileSub = _repository.watchDriverProfile(clean).listen(
      (profile) {
        final ride = _latest?.ride;
        if (ride == null || ride.driverId != clean) {
          return;
        }
        _latest = RideTripSnapshot(
          ride: ride,
          driverLocation: _latest?.driverLocation,
          driverProfile: profile,
        );
        _controller.add(_latest!);
      },
      onError: (_) {
        // Profile is optional; fall back to ride-doc fields.
      },
    );
  }

  Future<void> cancelRide() => _repository.cancelRide(rideId);

  Future<void> dispose() async {
    await _rideSub?.cancel();
    await _locationSub?.cancel();
    await _profileSub?.cancel();
    await _controller.close();
  }
}

/// Maps Firestore [RideStatus] → rider app route path.
String? routePathForRideStatus(
  RideStatus status, {
  bool paymentPaid = false,
}) {
  return switch (status) {
    RideStatus.requested => '/looking-for-driver',
    RideStatus.accepted => '/driver-found',
    RideStatus.arriving => '/arriving',
    RideStatus.waiting => '/ride-arrival',
    RideStatus.inProgress => '/driving-to-destination',
    RideStatus.confirmFare => paymentPaid ? '/ride-success' : '/ride-payment',
    RideStatus.completed => '/ride-success',
    RideStatus.cancelled => '/select-ride',
  };
}

int rideStatusRank(RideStatus status) {
  return switch (status) {
    RideStatus.requested => 0,
    RideStatus.accepted => 1,
    RideStatus.arriving => 2,
    RideStatus.waiting => 3,
    RideStatus.inProgress => 4,
    RideStatus.confirmFare => 5,
    RideStatus.completed => 6,
    RideStatus.cancelled => -1,
  };
}

bool shouldNavigateForStatus({
  required RideStatus currentScreen,
  required RideStatus fromFirestore,
}) {
  if (fromFirestore == RideStatus.cancelled) {
    return true;
  }
  // Never bounce back to looking-for-driver; that remounts matching and
  // creates duplicate ride requests.
  if (fromFirestore == RideStatus.requested) {
    return false;
  }
  if (currentScreen == RideStatus.inProgress) {
    return fromFirestore == RideStatus.confirmFare ||
        fromFirestore == RideStatus.completed;
  }
  return rideStatusRank(fromFirestore) > rideStatusRank(currentScreen);
}

/// Navigate when Firestore status moves past the screen this UI represents.
void navigateForRideSnapshot({
  required BuildContext context,
  required RideStatus screenStatus,
  required RideTripSnapshot snapshot,
  required Map<String, String> queryParameters,
}) {
  final ride = snapshot.ride;
  if (!shouldNavigateForStatus(
    currentScreen: screenStatus,
    fromFirestore: ride.status,
  )) {
    return;
  }

  final path = routePathForRideStatus(
    ride.status,
    paymentPaid: ride.isPaid,
  );
  if (path == null || !context.mounted) {
    return;
  }

  final params = Map<String, String>.from(queryParameters);
  params['rideId'] = ride.id;
  if (ride.driverId != null && ride.driverId!.trim().isNotEmpty) {
    params['driverId'] = ride.driverId!.trim();
  }

  context.go(Uri(path: path, queryParameters: params).toString());
}

Timestamp? readOptionalTimestamp(Object? value) {
  return timestampFrom(value);
}
