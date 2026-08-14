import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'google_maps_config.dart';
import 'google_maps_js_loader.dart';

Future<String?> reverseGeocodeWithGoogleMapsSdk(LatLng location) async {
  if (!GoogleMapsConfig.hasApiKey) {
    return null;
  }

  final sdkReady = await ensureGoogleMapsJsSdk(apiKey: GoogleMapsConfig.apiKey);
  if (!sdkReady) {
    return null;
  }

  try {
    final google = globalContext.getProperty<JSAny?>('google'.toJS);
    if (google == null || google.isUndefinedOrNull) {
      return null;
    }

    final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
    if (maps == null || maps.isUndefinedOrNull) {
      return null;
    }

    final geocoderConstructor = (maps as JSObject).getProperty<JSAny?>(
      'Geocoder'.toJS,
    );
    if (geocoderConstructor == null || geocoderConstructor.isUndefinedOrNull) {
      return null;
    }

    final geocoder = (geocoderConstructor as JSFunction)
        .callAsConstructor<JSObject>();
    final jsLocation = JSObject()
      ..setProperty('lat'.toJS, location.latitude.toJS)
      ..setProperty('lng'.toJS, location.longitude.toJS);
    final request = JSObject()..setProperty('location'.toJS, jsLocation);

    final response = await geocoder
        .callMethod<JSPromise<JSAny?>>('geocode'.toJS, request)
        .toDart;
    if (response == null || response.isUndefinedOrNull) {
      return null;
    }

    final results = (response as JSObject).getProperty<JSAny?>('results'.toJS);
    if (results == null || results.isUndefinedOrNull) {
      return null;
    }

    final geocodeResults = (results as JSArray<JSObject>).toDart;
    if (geocodeResults.isEmpty) {
      return null;
    }

    return _shortLabelFromJsGeocodeResult(geocodeResults.first);
  } on Object {
    return null;
  }
}

String? _shortLabelFromJsGeocodeResult(JSObject result) {
  final components = result.getProperty<JSAny?>('address_components'.toJS);
  String? streetNumber;
  String? route;
  String? neighborhood;
  String? sublocality;
  String? locality;
  String? administrativeArea;

  if (components != null && !components.isUndefinedOrNull) {
    for (final component in (components as JSArray<JSObject>).toDart) {
      final longName = component
          .getProperty<JSString?>('long_name'.toJS)
          ?.toDart;
      if (longName == null || longName.trim().isEmpty) {
        continue;
      }

      final typesValue = component.getProperty<JSAny?>('types'.toJS);
      if (typesValue == null || typesValue.isUndefinedOrNull) {
        continue;
      }

      final types = (typesValue as JSArray<JSString>).toDart
          .map((type) => type.toDart)
          .toSet();

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
  }

  if (route != null && streetNumber != null) {
    return '$streetNumber $route';
  }

  final label =
      route ?? neighborhood ?? sublocality ?? locality ?? administrativeArea;
  if (label != null) {
    return label;
  }

  final formattedAddress = result
      .getProperty<JSString?>('formatted_address'.toJS)
      ?.toDart;
  return formattedAddress?.split(',').first.trim();
}
