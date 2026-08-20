import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'google_maps_web_key.dart';

abstract final class GoogleMapsConfig {
  static const _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );
  static const _mapsApiKey = String.fromEnvironment('MAPS_API_KEY');
  static const apiKey = _googleMapsApiKey == ''
      ? _mapsApiKey
      : _googleMapsApiKey;
  static const _channel = MethodChannel('citiride/google_maps_config');

  static bool get hasApiKey => isUsableApiKey(apiKey);

  static Future<String?> runtimeApiKey() async {
    final compileTimeKey = apiKey.trim();
    if (isUsableApiKey(compileTimeKey)) {
      return compileTimeKey;
    }

    if (kIsWeb) {
      return readGoogleMapsWebApiKey();
    }

    try {
      final nativeKey = await _channel.invokeMethod<String>('apiKey');
      final cleanNativeKey = nativeKey?.trim();
      return isUsableApiKey(cleanNativeKey) ? cleanNativeKey : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static bool isUsableApiKey(String? value) {
    final key = value?.trim();
    return key != null && key.isNotEmpty && !key.contains('YOUR_');
  }

  /// Launch market. Expand [supportedRegionCodes] when entering new countries.
  /// Places autocomplete currently restricts suggestions to these ISO codes.
  static const countryCode = 'NG';
  static const supportedRegionCodes = <String>['NG'];
  static const defaultCenter = LatLng(6.3350, 5.6037);
  static const defaultZoom = 14.8;
}
