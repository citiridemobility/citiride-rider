import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'app/citiride_app.dart';
import 'core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAndroidGoogleMaps();
  unawaited(FirebaseBootstrap.initialize());

  runApp(
    CitirideApp(
      firebaseStatus: const FirebaseStatus.unconfigured('Firebase starting'),
    ),
  );
}

Future<void> _configureAndroidGoogleMaps() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  final mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is! GoogleMapsFlutterAndroid) {
    return;
  }

  try {
    await mapsImplementation.initializeWithRenderer(
      AndroidMapRenderer.platformDefault,
    );
  } on Object {
    // Keep app startup alive if Google Play services rejects explicit setup.
  }
}
