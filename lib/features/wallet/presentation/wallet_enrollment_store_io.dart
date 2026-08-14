import 'package:shared_preferences/shared_preferences.dart';

class WalletEnrollmentStore {
  WalletEnrollmentStore._();

  static final WalletEnrollmentStore instance = WalletEnrollmentStore._();

  static const _enrolledKey = 'citiride.wallet.isEnrolled';
  static const _passcodeKey = 'citiride.wallet.passcode';

  bool isEnrolled = false;
  String? passcode;
  String? pendingPasscode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedPasscode = prefs.getString(_passcodeKey);
      passcode = storedPasscode != null && storedPasscode.isNotEmpty
          ? storedPasscode
          : null;
      isEnrolled = prefs.getBool(_enrolledKey) == true || passcode != null;
    } on Object {
      // Keep in-memory defaults if persistence is unavailable.
    }
  }

  Future<void> setPendingPasscode(String code) async {
    pendingPasscode = code;
  }

  Future<void> completeEnrollment(String code) async {
    passcode = code;
    pendingPasscode = null;
    isEnrolled = true;
    await _persist();
  }

  bool verifyPasscode(String code) {
    return passcode != null && passcode == code;
  }

  Future<void> markEnrolled() async {
    isEnrolled = true;
    await _persist();
  }

  Future<void> clear() async {
    isEnrolled = false;
    passcode = null;
    pendingPasscode = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_enrolledKey);
      await prefs.remove(_passcodeKey);
    } on Object {
      // Clearing should never block logout/navigation.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enrolledKey, isEnrolled);
      if (passcode == null || passcode!.isEmpty) {
        await prefs.remove(_passcodeKey);
      } else {
        await prefs.setString(_passcodeKey, passcode!);
      }
    } on Object {
      // Enrollment should not fail because persistence is unavailable.
    }
  }
}
