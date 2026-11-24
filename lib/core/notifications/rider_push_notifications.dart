import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../firebase/firestore_paths.dart';

/// Registers the rider's FCM token and makes ride pushes audible in the
/// foreground. Notification-payload messages are rendered by Android/iOS when
/// the app is backgrounded or closed.
class RiderPushNotifications {
  RiderPushNotifications._();

  static final instance = RiderPushNotifications._();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  final _announcedAcceptedRideIds = <String>{};

  Future<void> configureForRider(String riderId) async {
    if (riderId.trim().isEmpty || Firebase.apps.isEmpty) {
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final permissions = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permissions.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(riderId, token);
      }

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen(
        (nextToken) => unawaited(_saveToken(riderId, nextToken)),
      );

      _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen((_) {
        SystemSound.play(SystemSoundType.alert);
      });
    } on Object {
      // A device without FCM/APNs configuration can still receive the live
      // Firestore ride-accepted sound below.
    }
  }

  void announceRideAccepted(String rideId) {
    if (rideId.isEmpty || !_announcedAcceptedRideIds.add(rideId)) {
      return;
    }
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _saveToken(String riderId, String token) {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.riders)
        .doc(riderId)
        .set({
          'fcmToken': token,
          'pushNotificationsEnabled': true,
          'pushTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
