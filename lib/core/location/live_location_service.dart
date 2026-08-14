import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LiveLocationService {
  const LiveLocationService();

  static const _targetAccuracyMeters = 20.0;

  Future<bool> ensurePermission({bool requestIfDenied = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfDenied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<LatLng?> lastKnownLatLng({bool requestIfDenied = false}) async {
    final granted = await ensurePermission(requestIfDenied: requestIfDenied);
    if (!granted) {
      return null;
    }

    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        return null;
      }

      return _toLatLng(position);
    } on Object {
      return null;
    }
  }

  Future<LatLng?> currentLatLng({bool requestIfDenied = true}) async {
    final granted = await ensurePermission(requestIfDenied: requestIfDenied);
    if (!granted) {
      return null;
    }

    try {
      final position = await _bestCurrentPosition();
      if (position == null) {
        return null;
      }

      return _toLatLng(position);
    } on Object {
      return null;
    }
  }

  Stream<LatLng> watchLatLng({bool requestIfDenied = false}) async* {
    final granted = await ensurePermission(requestIfDenied: requestIfDenied);
    if (!granted) {
      return;
    }

    yield* Geolocator.getPositionStream(
      locationSettings: _trackingLocationSettings,
    ).map(_toLatLng);
  }

  Future<Position?> _bestCurrentPosition() async {
    Position bestPosition = await Geolocator.getCurrentPosition(
      locationSettings: _singleFixLocationSettings,
    );

    if (_isTargetAccuracy(bestPosition)) {
      return bestPosition;
    }

    try {
      await for (final position
          in Geolocator.getPositionStream(
                locationSettings: _refinementLocationSettings,
              )
              .timeout(
                const Duration(seconds: 12),
                onTimeout: (sink) => sink.close(),
              )
              .take(8)) {
        if (_isBetterPosition(position, bestPosition)) {
          bestPosition = position;
        }

        if (_isTargetAccuracy(bestPosition)) {
          break;
        }
      }
    } on Object {
      return bestPosition;
    }

    return bestPosition;
  }

  bool _isTargetAccuracy(Position position) {
    return position.accuracy > 0 && position.accuracy <= _targetAccuracyMeters;
  }

  bool _isBetterPosition(Position candidate, Position current) {
    if (candidate.accuracy <= 0) {
      return false;
    }

    if (current.accuracy <= 0) {
      return true;
    }

    return candidate.accuracy < current.accuracy;
  }

  LatLng _toLatLng(Position position) {
    return LatLng(position.latitude, position.longitude);
  }

  LocationSettings get _singleFixLocationSettings {
    return _platformLocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: const Duration(seconds: 20),
    );
  }

  LocationSettings get _refinementLocationSettings {
    return _platformLocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: null,
    );
  }

  LocationSettings get _trackingLocationSettings {
    return _platformLocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      timeLimit: null,
    );
  }

  LocationSettings _platformLocationSettings({
    required LocationAccuracy accuracy,
    required int distanceFilter,
    required Duration? timeLimit,
  }) {
    if (kIsWeb) {
      return WebSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        maximumAge: Duration.zero,
        timeLimit: timeLimit,
      );
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 2),
        timeLimit: timeLimit,
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: timeLimit,
      ),
      _ => LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        timeLimit: timeLimit,
      ),
    };
  }
}
