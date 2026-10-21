import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:citiride/features/ride/domain/live_ride.dart';
import 'package:citiride/shared/widgets/citiride_google_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('nearby driver retains GPS heading and heartbeat time', () {
    final updatedAt = Timestamp.fromMillisecondsSinceEpoch(1760860800000);

    final driver = NearbyDriver.fromMap('driver-1', {
      'lat': 6.5244,
      'lng': 3.3792,
      'heading': 73.5,
      'updatedAt': updatedAt,
    });

    expect(driver.driverId, 'driver-1');
    expect(driver.lat, 6.5244);
    expect(driver.lng, 3.3792);
    expect(driver.heading, 73.5);
    expect(driver.updatedAt, updatedAt);
  });

  test('route polylines follow their Routes API vertices', () {
    final points = [
      const LatLng(6.5244, 3.3792),
      const LatLng(6.5250, 3.3800),
      const LatLng(6.5260, 3.3810),
    ];

    final polylines = citirideRoutePolylines(points);

    expect(polylines.length, 2);
    expect(polylines.every((polyline) => !polyline.geodesic), true);
    expect(
      polylines
          .singleWhere(
            (polyline) => polyline.polylineId.value == 'citiride-route',
          )
          .points,
      points,
    );
  });
}
