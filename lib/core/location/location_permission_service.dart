import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'live_location_service.dart';

class LocationPermissionService {
  const LocationPermissionService();

  static const MethodChannel _channel = MethodChannel(
    'citiride/location_permission',
  );

  Future<bool> requestWhenInUse() async {
    if (_isRunningWidgetTest) {
      try {
        final mockedResult = await _channel.invokeMethod<bool>(
          'requestWhenInUse',
        );
        if (mockedResult != null) {
          return mockedResult;
        }
      } on MissingPluginException {
        // Fall through to the real device permission flow.
      } on PlatformException {
        // Fall through to the real device permission flow.
      }
    }

    return const LiveLocationService().ensurePermission(requestIfDenied: true);
  }

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }
}
