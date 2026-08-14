import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'rider_profile_data.dart';

class RiderProfileStore {
  RiderProfileStore._();

  static final RiderProfileStore instance = RiderProfileStore._();

  static const _fileName = 'citiride_rider_profile.json';

  static const RiderProfile emptyProfile = RiderProfile(
    fullName: '',
    userName: '',
    phoneNumber: '',
    email: '',
  );

  final ValueNotifier<RiderProfile> profile = ValueNotifier<RiderProfile>(
    emptyProfile,
  );

  Future<void> load() async {
    if (_isRunningFlutterTest) {
      return;
    }

    try {
      final file = await _profileFile();
      if (!await file.exists()) {
        return;
      }

      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        return;
      }

      profile.value = RiderProfile.fromJson(value);
    } on Object {
      // Keep the in-memory default if persistence is unavailable.
    }
  }

  Future<void> update(RiderProfile nextProfile) async {
    profile.value = nextProfile;
    await _persist(nextProfile);
  }

  Future<void> clear() async {
    profile.value = emptyProfile;
    if (_isRunningFlutterTest) {
      return;
    }

    try {
      final file = await _profileFile();
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Profile reset should never block logout.
    }
  }

  Future<void> _persist(RiderProfile nextProfile) async {
    if (_isRunningFlutterTest) {
      return;
    }

    try {
      final file = await _profileFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(nextProfile.toJson()), flush: true);
    } on Object {
      // Profile edits should not fail because persistence is unavailable.
    }
  }

  Future<File> _profileFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
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
