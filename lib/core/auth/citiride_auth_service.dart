import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'citiride_otp_client.dart';

const citirideDemoVerificationCode = '968999';

enum CitirideAuthMethod { phone, email }

enum CitiridePhoneVerificationMode { firebase, demo }

class CitiridePhoneVerificationStart {
  const CitiridePhoneVerificationStart({
    required this.phoneNumber,
    required this.mode,
    this.verificationId,
    this.resendToken,
  });

  const CitiridePhoneVerificationStart.demo({required this.phoneNumber})
    : mode = CitiridePhoneVerificationMode.demo,
      verificationId = null,
      resendToken = null;

  final String phoneNumber;
  final CitiridePhoneVerificationMode mode;
  final String? verificationId;
  final int? resendToken;
}

class CitirideAuthResult {
  const CitirideAuthResult({
    required this.mode,
    this.email,
  });

  final CitiridePhoneVerificationMode mode;
  final String? email;
}

class CitirideAuthException implements Exception {
  const CitirideAuthException(this.message, {this.code});

  final String message;
  final String? code;

  bool get isInvalidCode {
    return code == 'invalid-verification-code' ||
        code == 'invalid_code_format' ||
        code == 'invalid-verification-id' ||
        code == 'session-expired';
  }

  @override
  String toString() => message;
}

class CitirideAuthService {
  CitirideAuthService({
    this._firestore,
    CitirideOtpClient? otpClient,
  }) : _otpClient = otpClient ?? CitirideOtpClient();

  final FirebaseFirestore? _firestore;
  final CitirideOtpClient _otpClient;

  static const _forceDemoEmailOtp = bool.fromEnvironment(
    'CITIRIDE_DEMO_EMAIL_OTP',
  );

  FirebaseFirestore get _firebaseFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  bool get _hasFirebaseApp => Firebase.apps.isNotEmpty;

  /// Phone SMS OTP is no longer used for login. Kept for older routes.
  Future<CitiridePhoneVerificationStart> startPhoneVerification({
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    return CitiridePhoneVerificationStart.demo(phoneNumber: phoneNumber);
  }

  Future<CitirideAuthResult> confirmPhoneCode({
    required String smsCode,
    required String phoneNumber,
    String? verificationId,
    CitiridePhoneVerificationMode mode = CitiridePhoneVerificationMode.demo,
  }) async {
    throw const CitirideAuthException(
      'Phone SMS verification is disabled. Use email OTP instead.',
      code: 'phone-auth-disabled',
    );
  }

  Future<CitirideOtpSendResult> startEmailVerification({
    required String email,
    CitirideOtpPurpose purpose = CitirideOtpPurpose.login,
  }) async {
    final cleanEmail = _cleanEmail(email);
    if (cleanEmail == null || !_isValidEmail(cleanEmail)) {
      throw const CitirideAuthException(
        'Enter a valid email address.',
        code: 'invalid-email',
      );
    }

    if (_forceDemoEmailOtp) {
      return CitirideOtpSendResult(
        email: cleanEmail,
        purpose: purpose,
        demoMode: true,
        demoCode: citirideDemoVerificationCode,
      );
    }

    try {
      return await _otpClient.sendOtp(email: cleanEmail, purpose: purpose);
    } on CitirideAuthException {
      rethrow;
    } on Object {
      throw const CitirideAuthException(
        'Unable to send verification code. Please try again.',
      );
    }
  }

  Future<CitirideAuthResult> confirmEmailCode({
    required String code,
    required String email,
    CitirideOtpPurpose purpose = CitirideOtpPurpose.login,
  }) async {
    final cleanEmail = _cleanEmail(email);
    if (cleanEmail == null || !_isValidEmail(cleanEmail)) {
      throw const CitirideAuthException(
        'Enter a valid email address.',
        code: 'invalid-email',
      );
    }

    if (_forceDemoEmailOtp) {
      if (code != citirideDemoVerificationCode) {
        throw const CitirideAuthException(
          'Incorrect code',
          code: 'invalid-verification-code',
        );
      }

      unawaited(_saveEmailProfile(email: cleanEmail));
      return CitirideAuthResult(
        mode: CitiridePhoneVerificationMode.demo,
        email: cleanEmail,
      );
    }

    try {
      await _otpClient.verifyOtp(
        email: cleanEmail,
        code: code,
        purpose: purpose,
      );
      // Never block login on Firestore — it was causing mobile OTP timeouts
      // after the server had already verified the code and sent welcome mail.
      unawaited(_saveEmailProfile(email: cleanEmail));
      return CitirideAuthResult(
        mode: CitiridePhoneVerificationMode.demo,
        email: cleanEmail,
      );
    } on CitirideAuthException {
      rethrow;
    } on Object {
      throw const CitirideAuthException(
        'Unable to verify code. Please try again.',
      );
    }
  }

  Future<void> _saveEmailProfile({required String email}) async {
    if (!_hasFirebaseApp) {
      return;
    }

    try {
      final docId = email.replaceAll(RegExp(r'[^a-z0-9@._+-]'), '_');
      await _firebaseFirestore
          .collection('riders')
          .doc(docId)
          .set({
            'email': email,
            'authProvider': 'email_otp',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 4));
    } on Object {
      // Auth success should not be blocked by profile persistence failure.
    }
  }

  String? _cleanEmail(String? email) {
    final value = email?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
  }
}
