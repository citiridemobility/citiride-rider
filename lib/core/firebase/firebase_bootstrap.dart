import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

@immutable
class FirebaseStatus {
  const FirebaseStatus.ready() : isReady = true, message = 'Firebase ready';

  const FirebaseStatus.unconfigured(this.message) : isReady = false;

  final bool isReady;
  final String message;
}

abstract final class FirebaseBootstrap {
  static Future<FirebaseStatus>? _initialization;

  static Future<FirebaseStatus> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<FirebaseStatus> _initialize() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return const FirebaseStatus.ready();
      }

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      return const FirebaseStatus.ready();
    } on UnsupportedError catch (error) {
      return FirebaseStatus.unconfigured(error.message ?? error.toString());
    } on FirebaseException catch (error) {
      return FirebaseStatus.unconfigured(error.message ?? error.code);
    } catch (error) {
      return FirebaseStatus.unconfigured(error.toString());
    }
  }
}
