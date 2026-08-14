import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../maps/google_maps_config.dart';
import 'citiride_route.dart';

class CitirideRouteService {
  CitirideRouteService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _routeTimeout = Duration(seconds: 9);

  Future<CitirideRoute> routeBetween({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final apiKey = await GoogleMapsConfig.runtimeApiKey();
    if (!GoogleMapsConfig.isUsableApiKey(apiKey)) {
      return CitirideRoute.estimated(origin: origin, destination: destination);
    }

    final uri = Uri.https(
      'routes.googleapis.com',
      '/directions/v2:computeRoutes',
    );
    final body = <String, Object?>{
      'origin': _waypoint(origin),
      'destination': _waypoint(destination),
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE',
      'polylineQuality': 'HIGH_QUALITY',
      'polylineEncoding': 'ENCODED_POLYLINE',
      'regionCode': GoogleMapsConfig.countryCode,
      'units': 'METRIC',
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey!,
              'X-Goog-FieldMask':
                  'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
            },
            body: jsonEncode(body),
          )
          .timeout(_routeTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CitirideRoute.estimated(
          origin: origin,
          destination: destination,
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = payload['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty || routes.first is! Map<String, dynamic>) {
        return CitirideRoute.estimated(
          origin: origin,
          destination: destination,
        );
      }

      final route = routes.first as Map<String, dynamic>;
      final encodedPolyline =
          (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
              as String?;
      final points = encodedPolyline == null || encodedPolyline.isEmpty
          ? <LatLng>[]
          : _decodePolyline(encodedPolyline);

      return CitirideRoute(
        origin: origin,
        destination: destination,
        points: points.isEmpty ? [origin, destination] : points,
        distanceMeters:
            (route['distanceMeters'] as num?)?.round() ??
            CitirideRoute.estimated(
              origin: origin,
              destination: destination,
            ).distanceMeters,
        duration:
            _parseGoogleDuration(route['duration'] as String?) ??
            CitirideRoute.estimated(
              origin: origin,
              destination: destination,
            ).duration,
      );
    } on Object {
      return CitirideRoute.estimated(origin: origin, destination: destination);
    }
  }

  Map<String, Object> _waypoint(LatLng location) {
    return {
      'location': {
        'latLng': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
      },
    };
  }

  Duration? _parseGoogleDuration(String? value) {
    if (value == null || !value.endsWith('s')) {
      return null;
    }

    final seconds = double.tryParse(value.substring(0, value.length - 1));
    if (seconds == null) {
      return null;
    }

    return Duration(milliseconds: (seconds * 1000).round());
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      final latitudeResult = _decodePolylineValue(encoded, index);
      index = latitudeResult.nextIndex;
      latitude += latitudeResult.value;

      final longitudeResult = _decodePolylineValue(encoded, index);
      index = longitudeResult.nextIndex;
      longitude += longitudeResult.value;

      points.add(LatLng(latitude / 1E5, longitude / 1E5));
    }

    return points;
  }

  _DecodedPolylineValue _decodePolylineValue(String encoded, int startIndex) {
    var result = 0;
    var shift = 0;
    var index = startIndex;
    int byte;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);

    final value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    return _DecodedPolylineValue(value: value, nextIndex: index);
  }
}

class _DecodedPolylineValue {
  const _DecodedPolylineValue({required this.value, required this.nextIndex});

  final int value;
  final int nextIndex;
}
