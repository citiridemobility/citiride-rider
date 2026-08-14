Future<bool> ensureGoogleMapsJsSdk({required String apiKey}) async {
  return apiKey.trim().isNotEmpty;
}
