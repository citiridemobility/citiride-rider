import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../../core/location/citiride_route.dart';

/// Fetches an authorized, traffic-aware route for the rider's active trip.
/// Google Routes credentials remain on the API; Flutter only receives the
/// resulting polyline, distance and ETA.
class CitirideTripNavigationService {
  CitirideTripNavigationService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? _configuredBaseUrl)
          .trim()
          .replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;

  static const _overrideBaseUrl = String.fromEnvironment(
    'CITIRIDE_OTP_API_URL',
  );
  static String get _configuredBaseUrl => _overrideBaseUrl.trim().isNotEmpty
      ? _overrideBaseUrl
      : CitirideOtpClient.productionBaseUrl;

  Future<CitirideRoute?> routeForRide({
    required String rideId,
    required LatLng destination,
  }) async {
    if (rideId.trim().isEmpty || _baseUrl.isEmpty) return null;

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/trips/route'),
            headers: await _headers(),
            body: jsonEncode({'rideId': rideId.trim()}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final payload = _decodeMap(response.body);
      final driver = _readPoint(payload['driverLocation']);
      final serverTarget = _readPoint(payload['target']) ?? destination;
      final route = payload['route'];
      if (driver == null || route is! Map) return null;

      final encoded = (route['encodedPolyline'] as String?)?.trim() ?? '';
      final points = encoded.isEmpty ? const <LatLng>[] : decodePolyline(encoded);
      final fallback = CitirideRoute.estimated(
        origin: driver,
        destination: serverTarget,
      );
      return CitirideRoute(
        origin: driver,
        destination: destination,
        points: points.isEmpty ? [driver, serverTarget] : points,
        distanceMeters:
            (route['distanceMeters'] as num?)?.round() ?? fallback.distanceMeters,
        duration: Duration(
          seconds: (route['durationSeconds'] as num?)?.round() ??
              fallback.duration.inSeconds,
        ),
      );
    } on Object {
      // Firestore still drives the live marker; keep it usable if the route
      // endpoint is temporarily unreachable.
      return null;
    }
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (Firebase.apps.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (user?.uid.isNotEmpty == true) headers['X-User-Id'] = user!.uid;
    }

    final fallbackUid = CitirideAuthService().currentUid;
    if (!headers.containsKey('X-User-Id') &&
        fallbackUid != null &&
        fallbackUid.isNotEmpty) {
      headers['X-User-Id'] = fallbackUid;
    }
    return headers;
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } on Object {
      return const {};
    }
  }

  LatLng? _readPoint(Object? raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    final lat = _decodeValue(encoded, index);
    index = lat.nextIndex;
    latitude += lat.value;

    final lng = _decodeValue(encoded, index);
    index = lng.nextIndex;
    longitude += lng.value;
    points.add(LatLng(latitude / 1E5, longitude / 1E5));
  }
  return points;
}

({int value, int nextIndex}) _decodeValue(String encoded, int startIndex) {
  var result = 0;
  var shift = 0;
  var index = startIndex;
  var byte = 0;
  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20 && index < encoded.length);
  final value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  return (value: value, nextIndex: index);
}
