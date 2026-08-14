import 'package:shared_preferences/shared_preferences.dart';

class CitirideSessionStore {
  const CitirideSessionStore();

  static const _authKey = 'citiride.authenticated';
  static const _onboardingKey = 'citiride.hasSeenOnboarding';

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

  Future<void> markAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_authKey, true);
      await prefs.setBool(_onboardingKey, true);
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
    } on Object {
      // Session persistence should never block navigation.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authKey);
      await prefs.remove(_onboardingKey);
    } on Object {
      // Session persistence should never block app launch/navigation.
    }
  }
}
