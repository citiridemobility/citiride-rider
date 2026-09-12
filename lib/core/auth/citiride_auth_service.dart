import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'citiride_otp_client.dart';
import '../../features/ride/domain/live_ride.dart';

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
    this.uid,
  });

  final CitiridePhoneVerificationMode mode;
  final String? email;
  final String? uid;
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
    this._auth,
    CitirideOtpClient? otpClient,
  }) : _otpClient = otpClient ?? CitirideOtpClient();

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final CitirideOtpClient _otpClient;

  static const _forceDemoEmailOtp = bool.fromEnvironment(
    'CITIRIDE_DEMO_EMAIL_OTP',
  );

  FirebaseFirestore get _firebaseFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;

  bool get _hasFirebaseApp => Firebase.apps.isNotEmpty;

  /// Current Firebase Auth uid when signed in after email OTP.
  String? get currentUid =>
      _hasFirebaseApp ? _firebaseAuth.currentUser?.uid : null;

  /// Stable rider id for Firestore rides (Auth uid, else email-derived).
  String? riderIdForEmail(String? email) {
    final uid = currentUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }
    final clean = _cleanEmail(email);
    if (clean == null) {
      return null;
    }
    return riderIdFromEmail(clean);
  }

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

  Future<bool> riderAccountExists({required String email}) async {
    final cleanEmail = _cleanEmail(email);
    if (cleanEmail == null || !_isValidEmail(cleanEmail)) {
      throw const CitirideAuthException(
        'Enter a valid email address.',
        code: 'invalid-email',
      );
    }

    if (_forceDemoEmailOtp) {
      return false;
    }

    try {
      return await _otpClient.riderAccountExists(email: cleanEmail);
    } on Object {
      return false;
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
        uid: currentUid,
      );
    }

    try {
      final verified = await _otpClient.verifyOtp(
        email: cleanEmail,
        code: code,
        purpose: purpose,
      );
      final uid = await _signInWithCustomToken(verified.firebaseCustomToken);
      // Never block login on Firestore — it was causing mobile OTP timeouts
      // after the server had already verified the code and sent welcome mail.
      unawaited(_saveEmailProfile(email: cleanEmail, uid: uid));
      return CitirideAuthResult(
        mode: CitiridePhoneVerificationMode.firebase,
        email: cleanEmail,
        uid: uid ?? currentUid,
      );
    } on CitirideAuthException {
      rethrow;
    } on Object {
      throw const CitirideAuthException(
        'Unable to verify code. Please try again.',
      );
    }
  }

  Future<String?> _signInWithCustomToken(String? token) async {
    final clean = token?.trim();
    if (clean == null || clean.isEmpty || !_hasFirebaseApp) {
      return null;
    }

    try {
      final credential = await _firebaseAuth
          .signInWithCustomToken(clean)
          .timeout(const Duration(seconds: 12));
      return credential.user?.uid;
    } on Object {
      // Local session + OTP success still stand if Auth sign-in fails.
      return null;
    }
  }

  Future<void> signOut() async {
    if (!_hasFirebaseApp) {
      return;
    }
    try {
      await _firebaseAuth.signOut().timeout(const Duration(seconds: 4));
    } on Object {
      // Local logout should never hang on Auth.
    }
  }

  Future<void> _saveEmailProfile({
    required String email,
    String? uid,
  }) async {
    if (!_hasFirebaseApp) {
      return;
    }

    try {
      final docId = (uid != null && uid.trim().isNotEmpty)
          ? uid.trim()
          : riderIdFromEmail(email);
      await _firebaseFirestore
          .collection('riders')
          .doc(docId)
          .set({
            'email': email,
            'authProvider': 'email_otp',
            'riderId': docId,
            'role': 'rider',
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
