import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../maps/google_maps_config.dart';
import '../maps/google_maps_reverse_geocoder.dart';
import '../maps/platform_reverse_geocoder.dart';
import 'citiride_place.dart';

class CitiridePlacesService {
  CitiridePlacesService({http.Client? client})
    : _client = client ?? http.Client(),
      _sessionToken = const Uuid().v4();

  final http.Client _client;
  String _sessionToken;

  static const _offlinePlaces = [
    CitiridePlace(
      title: 'Lagos Street',
      subtitle: 'Benin City',
      location: LatLng(6.3411, 5.6219),
    ),
    CitiridePlace(
      title: 'Benin City',
      subtitle: 'Nigeria',
      location: LatLng(6.3350, 5.6037),
    ),
    CitiridePlace(
      title: 'Afemai Transport Company',
      subtitle: 'Dawson Road, Benin City',
      location: LatLng(6.3339, 5.6252),
    ),
    CitiridePlace(
      title: 'Ring Road Bus Terminal',
      subtitle: 'Oba Market Road, Benin City 300102',
      location: LatLng(6.3374, 5.6149),
    ),
    CitiridePlace(
      title: 'Airport Road',
      subtitle: 'Benin City',
      location: LatLng(6.3177, 5.5981),
    ),
  ];

  List<CitiridePlace> defaultPlaces() => _offlinePlaces;

  void resetSession() {
    _sessionToken = const Uuid().v4();
  }

  Future<List<CitiridePlace>> autocomplete(
    String input, {
    LatLng? locationBias,
  }) async {
    final query = input.trim();
    if (query.length < 2) {
      return defaultPlaces();
    }

    final apiKey = await GoogleMapsConfig.runtimeApiKey();
    if (!GoogleMapsConfig.isUsableApiKey(apiKey)) {
      return _offlineMatches(query);
    }

    final uri = Uri.https('places.googleapis.com', '/v1/places:autocomplete');
    final body = <String, Object?>{
      'input': query,
      'sessionToken': _sessionToken,
      'includedRegionCodes': [GoogleMapsConfig.countryCode.toLowerCase()],
      if (locationBias != null)
        'locationBias': {
          'circle': {
            'center': {
              'latitude': locationBias.latitude,
              'longitude': locationBias.longitude,
            },
            'radius': 50000.0,
          },
        },
    };

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey!,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.place,'
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text.text,'
              'suggestions.placePrediction.structuredFormat.mainText.text,'
              'suggestions.placePrediction.structuredFormat.secondaryText.text',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _offlineMatches(query);
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = payload['suggestions'] as List<dynamic>? ?? [];

      return suggestions
          .map(_parseAutocompleteSuggestion)
          .whereType<CitiridePlace>()
          .toList(growable: false);
    } on Object {
      return _offlineMatches(query);
    }
  }

  Future<CitiridePlace> resolve(CitiridePlace suggestion) async {
    final placeId = suggestion.placeId;
    if (suggestion.location != null || placeId == null || placeId.isEmpty) {
      return suggestion;
    }

    final apiKey = await GoogleMapsConfig.runtimeApiKey();
    if (!GoogleMapsConfig.isUsableApiKey(apiKey)) {
      return suggestion;
    }

    final resourceName = placeId.startsWith('places/')
        ? placeId
        : 'places/$placeId';
    final uri = Uri.https('places.googleapis.com', '/v1/$resourceName');

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey!,
          'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return suggestion;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final locationPayload = payload['location'] as Map<String, dynamic>?;
      final displayName = payload['displayName'] as Map<String, dynamic>?;
      final latitude = (locationPayload?['latitude'] as num?)?.toDouble();
      final longitude = (locationPayload?['longitude'] as num?)?.toDouble();

      return suggestion.copyWith(
        title: (displayName?['text'] as String?) ?? suggestion.title,
        subtitle: payload['formattedAddress'] as String? ?? suggestion.subtitle,
        location: latitude != null && longitude != null
            ? LatLng(latitude, longitude)
            : suggestion.location,
      );
    } on Object {
      return suggestion;
    }
  }

  Future<String?> reverseGeocodeLabel(LatLng location) async {
    final sdkLabel = await reverseGeocodeWithGoogleMapsSdk(location);
    if (sdkLabel?.trim().isNotEmpty == true) {
      return sdkLabel!.trim();
    }

    final apiKey = await GoogleMapsConfig.runtimeApiKey();
    if (GoogleMapsConfig.isUsableApiKey(apiKey)) {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${location.latitude},${location.longitude}',
        'key': apiKey!,
      });

      try {
        final response = await _client.get(uri);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          if (payload['status'] == 'OK') {
            final results = payload['results'] as List<dynamic>? ?? [];
            if (results.isNotEmpty) {
              final label = _shortLabelFromGeocodeResult(results.first);
              if (label?.trim().isNotEmpty == true) {
                return label!.trim();
              }
            }
          }
        }
      } on Object {
        // Fall through to the platform geocoder.
      }
    }

    final platformLabel = await reverseGeocodeWithPlatform(location);
    final cleanPlatformLabel = platformLabel?.trim();
    if (cleanPlatformLabel != null && cleanPlatformLabel.isNotEmpty) {
      return cleanPlatformLabel;
    }

    return null;
  }

  List<CitiridePlace> _offlineMatches(String query) {
    final normalized = query.toLowerCase();
    return _offlinePlaces
        .where((place) {
          return place.title.toLowerCase().contains(normalized) ||
              (place.subtitle?.toLowerCase().contains(normalized) ?? false);
        })
        .toList(growable: false);
  }

  CitiridePlace? _parseAutocompleteSuggestion(Object? item) {
    if (item is! Map<String, dynamic>) {
      return null;
    }

    final prediction = item['placePrediction'] as Map<String, dynamic>?;
    if (prediction == null) {
      return null;
    }

    final structured =
        prediction['structuredFormat'] as Map<String, dynamic>? ?? {};
    final mainText = structured['mainText'] as Map<String, dynamic>?;
    final secondaryText = structured['secondaryText'] as Map<String, dynamic>?;
    final text = prediction['text'] as Map<String, dynamic>?;
    final title = mainText?['text'] as String? ?? text?['text'] as String?;

    if (title == null || title.trim().isEmpty) {
      return null;
    }

    return CitiridePlace(
      title: title,
      subtitle: secondaryText?['text'] as String?,
      placeId:
          prediction['placeId'] as String? ?? prediction['place'] as String?,
    );
  }

  String? _shortLabelFromGeocodeResult(Object? item) {
    if (item is! Map<String, dynamic>) {
      return null;
    }

    final components = item['address_components'] as List<dynamic>? ?? [];
    String? streetNumber;
    String? route;
    String? neighborhood;
    String? sublocality;
    String? locality;
    String? administrativeArea;

    for (final component in components.whereType<Map<String, dynamic>>()) {
      final types = (component['types'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toSet();
      final longName = component['long_name'] as String?;
      if (longName == null || longName.trim().isEmpty) {
        continue;
      }

      if (types.contains('street_number')) {
        streetNumber ??= longName;
      } else if (types.contains('route')) {
        route ??= longName;
      } else if (types.contains('neighborhood')) {
        neighborhood ??= longName;
      } else if (types.contains('sublocality') ||
          types.contains('sublocality_level_1')) {
        sublocality ??= longName;
      } else if (types.contains('locality')) {
        locality ??= longName;
      } else if (types.contains('administrative_area_level_1')) {
        administrativeArea ??= longName;
      }
    }

    if (route != null && streetNumber != null) {
      return '$streetNumber $route';
    }

    final label =
        route ?? neighborhood ?? sublocality ?? locality ?? administrativeArea;
    if (label != null) {
      return label;
    }

    final formattedAddress = item['formatted_address'] as String?;
    return formattedAddress?.split(',').first.trim();
  }
}
