import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'citiride_auth_service.dart';

enum CitirideOtpPurpose { login, wallet, resetPin, withdraw }

class CitirideOtpClient {
  CitirideOtpClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = _resolveBaseUrl(baseUrl);

  /// Production OTP API on Railway. Override with:
  /// `--dart-define=CITIRIDE_OTP_API_URL=https://...`
  static const productionBaseUrl =
      'https://otp-api-production-db79.up.railway.app';

  static const _configuredBaseUrl = String.fromEnvironment(
    'CITIRIDE_OTP_API_URL',
  );

  final http.Client _client;
  final String _baseUrl;

  bool get hasConfiguredBaseUrl => _baseUrl.isNotEmpty;

  /// Host currently used for OTP requests (for diagnostics).
  String get baseUrl => _baseUrl;

  static String _resolveBaseUrl(String? override) {
    final configured = (override ?? _configuredBaseUrl).trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }

    // Default to the hosted API so debug/web runs don't hit a stale local
    // otp-api process and send the old plain email template.
    // Override with: --dart-define=CITIRIDE_OTP_API_URL=http://127.0.0.1:8787
    return productionBaseUrl;
  }

  Future<CitirideOtpSendResult> sendOtp({
    required String email,
    required CitirideOtpPurpose purpose,
  }) async {
    final response = await _post('/v1/otp/send', {
      'email': email,
      'purpose': _purposeValue(purpose),
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = _decodeMap(response.body);
      return CitirideOtpSendResult(
        email: (body['email'] as String?) ?? email,
        purpose: purpose,
        demoMode: body['demoMode'] == true,
        demoCode: body['demoCode'] as String?,
        expiresInMs: (body['expiresInMs'] as num?)?.toInt(),
      );
    }

    throw _mapError(response);
  }

  Future<CitirideOtpVerifyResult> verifyOtp({
    required String email,
    required String code,
    required CitirideOtpPurpose purpose,
  }) async {
    final response = await _post('/v1/otp/verify', {
      'email': email,
      'code': code,
      'purpose': _purposeValue(purpose),
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = _decodeMap(response.body);
      final token = (body['firebaseCustomToken'] as String?)?.trim();
      return CitirideOtpVerifyResult(
        email: (body['email'] as String?) ?? email,
        purpose: purpose,
        firebaseCustomToken: token != null && token.isNotEmpty ? token : null,
      );
    }

    throw _mapError(response);
  }

  /// Sent after wallet passcode enrollment completes.
  Future<void> congratulateWalletCreated({
    required String email,
    String role = 'rider',
  }) async {
    final response = await _post('/v1/wallet/congratulate', {
      'email': email,
      'role': role,
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw _mapError(response);
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    if (!hasConfiguredBaseUrl) {
      throw const CitirideAuthException(
        'OTP API URL is not configured.',
        code: 'misconfigured',
      );
    }

    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } on CitirideAuthException {
      rethrow;
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('OTP API request failed ($_baseUrl$path): $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      throw CitirideAuthException(
        'Could not reach the verification service at $_baseUrl. '
        'Check your internet connection and try again.',
        code: 'network-error',
      );
    }
  }

  CitirideAuthException _mapError(http.Response response) {
    final body = _decodeMap(response.body);
    final code = (body['error'] as String?) ?? 'server_error';
    final message =
        (body['message'] as String?) ??
        'Unable to complete verification. Please try again.';

    return CitirideAuthException(message, code: code);
  }

  Map<String, dynamic> _decodeMap(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) {
        return value;
      }
    } on Object {
      // Fall through.
    }
    return const <String, dynamic>{};
  }

  String _purposeValue(CitirideOtpPurpose purpose) {
    return switch (purpose) {
      CitirideOtpPurpose.login => 'login',
      CitirideOtpPurpose.wallet => 'wallet',
      CitirideOtpPurpose.resetPin => 'reset_pin',
      CitirideOtpPurpose.withdraw => 'withdraw',
    };
  }
}

class CitirideOtpSendResult {
  const CitirideOtpSendResult({
    required this.email,
    required this.purpose,
    required this.demoMode,
    this.demoCode,
    this.expiresInMs,
  });

  final String email;
  final CitirideOtpPurpose purpose;
  final bool demoMode;
  final String? demoCode;
  final int? expiresInMs;
}

class CitirideOtpVerifyResult {
  const CitirideOtpVerifyResult({
    required this.email,
    required this.purpose,
    this.firebaseCustomToken,
  });

  final String email;
  final CitirideOtpPurpose purpose;
  final String? firebaseCustomToken;
}
