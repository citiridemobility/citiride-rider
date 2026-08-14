class CitirideSessionStore {
  const CitirideSessionStore();

  Future<bool> hasCompletedAuth() async => false;

  Future<bool> hasSeenOnboarding() async => false;

  Future<void> markAuthenticated() async {}

  Future<void> markOnboardingSeen() async {}

  Future<void> clearAuth() async {}

  Future<void> clear() async {}
}
