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
  });

  final LiveRide ride;
  final DriverLocation? driverLocation;

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
  String? _watchingDriverId;
  RideTripSnapshot? _latest;
  final _controller = StreamController<RideTripSnapshot>.broadcast();

  Stream<RideTripSnapshot> get snapshots => _controller.stream;
  RideTripSnapshot? get latest => _latest;

  void start() {
    _rideSub?.cancel();
    _rideSub = _repository.watchRide(rideId).listen(
      (ride) {
        _latest = RideTripSnapshot(
          ride: ride,
          driverLocation: _latest?.driverLocation,
        );
        _controller.add(_latest!);
        _syncDriverLocationWatch(ride.driverId);
      },
      onError: _controller.addError,
    );
  }

  void _syncDriverLocationWatch(String? driverId) {
    final clean = driverId?.trim();
    if (clean == null || clean.isEmpty) {
      unawaited(_locationSub?.cancel() ?? Future<void>.value());
      _locationSub = null;
      _watchingDriverId = null;
      return;
    }
    if (clean == _watchingDriverId) {
      return;
    }
    _watchingDriverId = clean;
    unawaited(_locationSub?.cancel() ?? Future<void>.value());
    _locationSub = _repository.watchDriverLocation(clean).listen(
      (location) {
        final ride = _latest?.ride;
        if (ride == null) {
          return;
        }
        _latest = RideTripSnapshot(ride: ride, driverLocation: location);
        _controller.add(_latest!);
      },
      onError: (_) {
        // Driver location is optional; ride status still drives the UI.
      },
    );
  }

  Future<void> cancelRide() => _repository.cancelRide(rideId);

  Future<void> dispose() async {
    await _rideSub?.cancel();
    await _locationSub?.cancel();
    await _controller.close();
  }
}

/// Maps Firestore [RideStatus] → rider app route path.
String? routePathForRideStatus(RideStatus status) {
  return switch (status) {
    RideStatus.requested => '/looking-for-driver',
    RideStatus.accepted => '/driver-found',
    RideStatus.arriving => '/arriving',
    RideStatus.waiting => '/ride-arrival',
    RideStatus.inProgress => '/driving-to-destination',
    RideStatus.confirmFare || RideStatus.completed => '/ride-success',
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

  final path = routePathForRideStatus(ride.status);
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
