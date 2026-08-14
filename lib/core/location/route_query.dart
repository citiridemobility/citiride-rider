import 'package:google_maps_flutter/google_maps_flutter.dart';

LatLng? latLngFromQuery(Map<String, String> query, String prefix) {
  final latitude = double.tryParse(query['${prefix}Lat'] ?? '');
  final longitude = double.tryParse(query['${prefix}Lng'] ?? '');
  if (latitude == null || longitude == null) {
    return null;
  }

  return LatLng(latitude, longitude);
}

Map<String, String> latLngToQuery(String prefix, LatLng? location) {
  if (location == null) {
    return const {};
  }

  return {
    '${prefix}Lat': location.latitude.toStringAsFixed(7),
    '${prefix}Lng': location.longitude.toStringAsFixed(7),
  };
}
