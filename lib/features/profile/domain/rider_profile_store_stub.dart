import 'package:flutter/foundation.dart';

import 'rider_profile_data.dart';

class RiderProfileStore {
  RiderProfileStore._();

  static final RiderProfileStore instance = RiderProfileStore._();

  static const RiderProfile emptyProfile = RiderProfile(
    fullName: '',
    userName: '',
    phoneNumber: '',
    email: '',
  );

  final ValueNotifier<RiderProfile> profile = ValueNotifier<RiderProfile>(
    emptyProfile,
  );

  Future<void> load() async {}

  Future<void> update(RiderProfile nextProfile) async {
    profile.value = nextProfile;
  }

  Future<void> clear() async {
    profile.value = emptyProfile;
  }
}
