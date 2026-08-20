class CitirideSessionStore {
  const CitirideSessionStore();

  Future<bool> hasCompletedAuth() async => false;

  Future<bool> hasSeenOnboarding() async => false;

  Future<String?> signedInEmail() async => null;

  Future<void> markAuthenticated({String? email}) async {}

  Future<void> markOnboardingSeen() async {}

  Future<void> clearAuth() async {}

  Future<void> clear() async {}
}
