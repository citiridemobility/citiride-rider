import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'rider_profile_data.dart';

class RiderProfileStore {
  RiderProfileStore._();

  static final RiderProfileStore instance = RiderProfileStore._();

  static const _legacyFileName = 'citiride_rider_profile.json';
  static const _fileNamePrefix = 'citiride_rider_profile_';

  static const RiderProfile emptyProfile = RiderProfile(
    fullName: '',
    userName: '',
    phoneNumber: '',
    email: '',
  );

  final ValueNotifier<RiderProfile> profile = ValueNotifier<RiderProfile>(
    emptyProfile,
  );

  String? _activeEmail;
  String? _activeRemoteDocumentId;

  Future<void> load() async {
    if (_isRunningFlutterTest) {
      return;
    }

    try {
      final loaded = await _readProfile(await _legacyProfileFile());
      if (loaded == null) {
        return;
      }

      profile.value = loaded;
    } on Object {
      // Keep the in-memory default if persistence is unavailable.
    }
  }

  /// Restores the profile for the account that has just authenticated.
  ///
  /// Device storage is keyed by email so it can provide an immediate offline
  /// value. When Firebase is available, the authenticated rider document is
  /// then the source of truth and refreshes that local copy.
  Future<void> restoreForAccount({required String email, String? uid}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      return;
    }

    _activeEmail = cleanEmail;
    _activeRemoteDocumentId = _documentIdFor(email: cleanEmail, uid: uid);

    if (_isRunningFlutterTest) {
      profile.value = profile.value.copyWith(email: cleanEmail);
      return;
    }

    final local = await _readProfile(await _profileFileForEmail(cleanEmail));
    if (local != null) {
      profile.value = local.copyWith(
        email: local.email.isEmpty ? cleanEmail : local.email,
      );
    } else {
      profile.value = emptyProfile.copyWith(email: cleanEmail);
    }

    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('riders')
          .doc(_activeRemoteDocumentId)
          .get()
          .timeout(const Duration(seconds: 4));
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return;
      }

      final restored = RiderProfile.fromJson(data).copyWith(
        email: (data['email'] as String?)?.trim().isNotEmpty == true
            ? (data['email'] as String).trim().toLowerCase()
            : cleanEmail,
      );
      profile.value = restored;
      await _persistLocal(restored);
    } on Object {
      // The local profile remains available when the network is unavailable.
    }
  }

  Future<void> update(RiderProfile nextProfile) async {
    profile.value = nextProfile;
    await _persist(nextProfile);
    await _persistRemote(nextProfile);
  }

  Future<void> clear() async {
    profile.value = emptyProfile;
    _activeEmail = null;
    _activeRemoteDocumentId = null;
    // Keep account-keyed profile files. They are restored only after the same
    // account authenticates again, so logout cannot expose them to another
    // rider while still allowing an offline returning rider to continue.
  }

  Future<void> _persist(RiderProfile nextProfile) async {
    if (_isRunningFlutterTest) {
      return;
    }

    try {
      final email = _activeEmail ?? nextProfile.email.trim().toLowerCase();
      if (email.isEmpty) {
        return;
      }
      _activeEmail = email;
      await _persistLocal(nextProfile);
    } on Object {
      // Profile edits should not fail because persistence is unavailable.
    }
  }

  Future<void> _persistLocal(RiderProfile nextProfile) async {
    final email = _activeEmail ?? nextProfile.email.trim().toLowerCase();
    if (email.isEmpty) {
      return;
    }
    final file = await _profileFileForEmail(email);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(nextProfile.toJson()), flush: true);
  }

  Future<void> _persistRemote(RiderProfile nextProfile) async {
    final documentId = _activeRemoteDocumentId;
    final email = (_activeEmail ?? nextProfile.email).trim().toLowerCase();
    if (documentId == null || documentId.isEmpty || email.isEmpty) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('riders')
          .doc(documentId)
          .set({
            ...nextProfile.toJson(),
            'email': email,
            'riderId': documentId,
            'role': 'rider',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 4));
    } on Object {
      // An offline edit is retained locally and can be refreshed next login.
    }
  }

  Future<RiderProfile?> _readProfile(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      return null;
    }
    return RiderProfile.fromJson(value);
  }

  Future<File> _legacyProfileFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_legacyFileName');
  }

  Future<File> _profileFileForEmail(String email) async {
    final directory = await getApplicationSupportDirectory();
    final safeEmail = base64Url.encode(utf8.encode(email)).replaceAll('=', '');
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '$_fileNamePrefix$safeEmail.json',
    );
  }

  static String _documentIdFor({required String email, String? uid}) {
    final cleanUid = uid?.trim();
    if (cleanUid != null && cleanUid.isNotEmpty) {
      return cleanUid;
    }
    return email.replaceAll(RegExp(r'[^a-z0-9@._+-]'), '_');
  }

  static bool get _isRunningFlutterTest {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true' ||
          Platform.resolvedExecutable.toLowerCase().contains('flutter_tester');
    } on Object {
      return false;
    }
  }
}
