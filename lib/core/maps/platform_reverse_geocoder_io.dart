import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<String?> reverseGeocodeWithPlatform(LatLng location) async {
  try {
    final placemarks = await placemarkFromCoordinates(
      location.latitude,
      location.longitude,
    );
    if (placemarks.isEmpty) {
      return null;
    }

    final place = placemarks.first;
    final streetNumber = place.subThoroughfare?.trim();
    final route = place.thoroughfare?.trim();
    if (route != null && route.isNotEmpty) {
      if (streetNumber != null && streetNumber.isNotEmpty) {
        return '$streetNumber $route';
      }
      return route;
    }

    final candidates = <String?>[
      place.street,
      place.name,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ];

    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
  } on Object {
    return null;
  }

  return null;
}
