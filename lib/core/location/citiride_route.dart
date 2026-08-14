import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class CitirideRoute {
  const CitirideRoute({
    required this.origin,
    required this.destination,
    required this.points,
    required this.distanceMeters,
    required this.duration,
    this.isEstimated = false,
  });

  final LatLng origin;
  final LatLng destination;
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;
  final bool isEstimated;

  factory CitirideRoute.estimated({
    required LatLng origin,
    required LatLng destination,
  }) {
    final distanceMeters = _distanceInMeters(origin, destination).round();
    const averageUrbanSpeedKmh = 28.0;
    final seconds = math
        .max(60, (distanceMeters / 1000) / averageUrbanSpeedKmh * 3600)
        .round();

    return CitirideRoute(
      origin: origin,
      destination: destination,
      points: _estimatedPath(origin, destination),
      distanceMeters: distanceMeters,
      duration: Duration(seconds: seconds),
      isEstimated: true,
    );
  }

  LatLng get center {
    final bounds = latLngBounds;
    return LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }

  LatLngBounds get latLngBounds {
    final allPoints = points.isEmpty ? [origin, destination] : points;
    var minLat = allPoints.first.latitude;
    var maxLat = allPoints.first.latitude;
    var minLng = allPoints.first.longitude;
    var maxLng = allPoints.first.longitude;

    for (final point in allPoints.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  String get distanceText {
    if (distanceMeters < 1000) {
      return '${distanceMeters}m';
    }

    final kilometers = distanceMeters / 1000;
    final precision = kilometers >= 10 ? 0 : 1;
    return '${kilometers.toStringAsFixed(precision)}km';
  }

  String get durationText {
    final minutes = math.max(1, (duration.inSeconds / 60).ceil());
    return minutes == 1 ? '1 min' : '$minutes mins';
  }

  String get pickupEtaText {
    final minutes = math.max(2, (duration.inMinutes * 0.38).round());
    return minutes == 1 ? '1 min' : '$minutes mins';
  }

  String get arrivalText {
    final arrival = DateTime.now().add(duration);
    final hour = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final suffix = arrival.hour >= 12 ? 'pm' : 'am';
    return 'Arrive by $hour:$minute$suffix';
  }

  static List<LatLng> _estimatedPath(LatLng origin, LatLng destination) {
    final deltaLat = destination.latitude - origin.latitude;
    final deltaLng = destination.longitude - origin.longitude;
    final length = math.sqrt((deltaLat * deltaLat) + (deltaLng * deltaLng));
    if (length <= 0.000001) {
      return [origin, destination];
    }

    final distanceMeters = _distanceInMeters(origin, destination);
    final curve = math.min(0.0028, math.max(0.00045, distanceMeters / 2200000));
    final normalLat = -deltaLng / length;
    final normalLng = deltaLat / length;

    LatLng pointAt(double t, double bend) {
      final ease = t * t * (3 - (2 * t));
      final arc = math.sin(t * math.pi) * curve * bend;
      return LatLng(
        origin.latitude + (deltaLat * ease) + (normalLat * arc),
        origin.longitude + (deltaLng * ease) + (normalLng * arc),
      );
    }

    return [
      origin,
      pointAt(0.24, 0.75),
      pointAt(0.48, 1.0),
      pointAt(0.72, 0.64),
      destination,
    ];
  }

  static double _distanceInMeters(LatLng first, LatLng second) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _degreesToRadians(first.latitude);
    final lat2 = _degreesToRadians(second.latitude);
    final deltaLat = _degreesToRadians(second.latitude - first.latitude);
    final deltaLng = _degreesToRadians(second.longitude - first.longitude);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
