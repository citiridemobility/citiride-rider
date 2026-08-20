import 'package:shared_preferences/shared_preferences.dart';

class CitirideSessionStore {
  const CitirideSessionStore();

  static const _authKey = 'citiride.authenticated';
  static const _onboardingKey = 'citiride.hasSeenOnboarding';
  static const _emailKey = 'citiride.auth.email';

  Future<bool> hasCompletedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_authKey) == true;
    } on Object {
      return false;
    }
  }

  Future<bool> hasSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingKey) == true;
    } on Object {
      return false;
    }
  }

  Future<String?> signedInEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey)?.trim().toLowerCase();
      if (email == null || email.isEmpty) {
        return null;
      }
      return email;
    } on Object {
      return null;
    }
  }

  Future<void> markAuthenticated({String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_authKey, true);
      await prefs.setBool(_onboardingKey, true);
      final cleanEmail = email?.trim().toLowerCase();
      if (cleanEmail != null && cleanEmail.isNotEmpty) {
        await prefs.setString(_emailKey, cleanEmail);
      }
    } on Object {
      // Auth should not fail because local persistence is unavailable.
    }
  }

  Future<void> markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingKey, true);
    } on Object {
      // Onboarding should not fail because local persistence is unavailable.
    }
  }

  /// Signs the user out but keeps onboarding-seen so they return to welcome/login.
  Future<void> clearAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_authKey, false);
      await prefs.remove(_emailKey);
    } on Object {
      // Session persistence should never block navigation.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authKey);
      await prefs.remove(_onboardingKey);
      await prefs.remove(_emailKey);
    } on Object {
      // Session persistence should never block app launch/navigation.
    }
  }
}
