import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../profile/domain/rider_profile.dart';
import 'widgets/auth_number_pad.dart';

class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({
    super.key,
    this.phoneDigits = '',
    this.phoneNumber,
    this.email,
    this.intent = 'signup',
    this.authMethod = CitirideAuthMethod.phone,
    this.verificationId,
    this.resendToken,
    this.verificationMode = CitiridePhoneVerificationMode.demo,
  });

  final String phoneDigits;
  final String? phoneNumber;
  final String? email;
  final String intent;
  final CitirideAuthMethod authMethod;
  final String? verificationId;
  final int? resendToken;
  final CitiridePhoneVerificationMode verificationMode;

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

enum _CodeResult { idle, correct, incorrect }

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  static const _codeLength = 6;
  static const _resendStartSeconds = 30;
  static const _successDelay = Duration(seconds: 2);
  static const _verificationTimeout = Duration(seconds: 45);

  final _authService = CitirideAuthService();
  final _sessionStore = const CitirideSessionStore();

  String _code = '';
  int _resendSeconds = _resendStartSeconds;
  Timer? _resendTimer;
  _CodeResult _result = _CodeResult.idle;
  bool _isSubmitting = false;
  bool _hideVerificationContent = false;
  bool _loadingDialogVisible = false;

  bool get _isComplete => _code.length == _codeLength;

  bool get _canContinue =>
      _isComplete && _result != _CodeResult.incorrect && !_isSubmitting;

  bool get _isEmailAuth => widget.authMethod == CitirideAuthMethod.email;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        setState(() {
          _resendSeconds = 0;
        });
        timer.cancel();
        return;
      }

      setState(() {
        _resendSeconds -= 1;
      });
    });
  }

  void _appendDigit(String digit) {
    if (_isSubmitting || _code.length >= _codeLength) {
      return;
    }

    setState(() {
      _result = _CodeResult.idle;
      _code += digit;
    });
  }

  void _deleteLastDigit() {
    if (_isSubmitting || _code.isEmpty) {
      return;
    }

    setState(() {
      _result = _CodeResult.idle;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _verifyCode() async {
    if (!_canContinue) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _result = _CodeResult.idle;
    });

    _showLoadingDialog();

    try {
      await _confirmEnteredCode().timeout(
        _verificationTimeout,
        onTimeout: () => throw const CitirideAuthException(
          'Verification is taking too long. Please try again.',
          code: 'timeout',
        ),
      );
    } on CitirideAuthException catch (error) {
      _dismissLoadingDialog();

      if (!mounted) {
        return;
      }

      final isInvalidCode = error.isInvalidCode;
      setState(() {
        _result = isInvalidCode ? _CodeResult.incorrect : _CodeResult.idle;
        _isSubmitting = false;
      });

      if (!isInvalidCode) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }

    if (!mounted) {
      _dismissLoadingDialog();
      return;
    }

    await _sessionStore
        .markAuthenticated(
          email: _isEmailAuth ? _emailAddress : null,
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );

    if (_isEmailAuth) {
      final profile = RiderProfileStore.instance.profile.value;
      await RiderProfileStore.instance
          .update(profile.copyWith(email: _emailAddress))
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }

    setState(() {
      _result = _CodeResult.correct;
    });

    if (widget.intent == 'login') {
      _dismissLoadingDialog();
      if (mounted) {
        context.go('/set-location');
      }
      return;
    }

    await _showSignupSuccessFlow();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  Future<void> _confirmEnteredCode() {
    if (_isEmailAuth) {
      return _authService.confirmEmailCode(
        code: _code,
        email: _emailAddress,
        purpose: CitirideOtpPurpose.login,
      );
    }

    throw const CitirideAuthException(
      'Phone SMS verification is disabled. Use email OTP instead.',
      code: 'phone-auth-disabled',
    );
  }

  void _showLoadingDialog() {
    _loadingDialogVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.74),
        builder: (dialogContext) {
          return const _VerificationLoadingDialog();
        },
      ).whenComplete(() {
        _loadingDialogVisible = false;
      }),
    );
  }

  void _dismissLoadingDialog() {
    if (!_loadingDialogVisible || !mounted) {
      return;
    }

    _loadingDialogVisible = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _showSignupSuccessFlow() async {
    await Future<void>.delayed(_successDelay);

    if (!mounted) {
      return;
    }

    _dismissLoadingDialog();

    final shouldProceed = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (sheetContext) {
        return _SignupSuccessSheet(
          onProceed: () {
            if (mounted) {
              setState(() {
                _hideVerificationContent = true;
              });
            }
            Navigator.of(sheetContext).pop(true);
          },
        );
      },
    );

    if (!mounted || shouldProceed != true) {
      return;
    }

    context.go('/set-location');
  }

  Future<void> _resendCode() async {
    if (_isSubmitting ||
        (_resendSeconds > 0 && _result != _CodeResult.correct)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      if (_isEmailAuth) {
        await _authService.startEmailVerification(
          email: _emailAddress,
          purpose: CitirideOtpPurpose.login,
        );
      } else {
        throw const CitirideAuthException(
          'Phone SMS verification is disabled. Use email OTP instead.',
          code: 'phone-auth-disabled',
        );
      }
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _code = '';
      _result = _CodeResult.idle;
      _resendSeconds = _resendStartSeconds;
      _isSubmitting = false;
    });
    _startResendCountdown();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    final email = _emailAddress;
    context.go(
      Uri(
        path: '/enter-number',
        queryParameters: {
          'intent': widget.intent == 'login' ? 'login' : 'signup',
          if (email.isNotEmpty) 'email': email,
        },
      ).toString(),
    );
  }

  String get _emailAddress {
    final provided = widget.email?.trim();
    if (provided == null || provided.isEmpty) {
      return 'rider@example.com';
    }

    return provided.toLowerCase();
  }

  String get _formattedPhoneNumber => _formatNigerianPhone(widget.phoneDigits);

  static String _formatNigerianPhone(String digits) {
    final cleaned = digits.replaceAll(RegExp(r'\D'), '');
    final normalized = cleaned.length == 11 && cleaned.startsWith('0')
        ? cleaned.substring(1)
        : cleaned;

    if (normalized.length >= 10) {
      return '+234 ${normalized.substring(0, 3)} '
          '${normalized.substring(3, 7)} ${normalized.substring(7, 10)}';
    }

    return '+234 903 4627 499';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.citirideBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.citirideBlack,
      ),
      child: Scaffold(
        backgroundColor: AppColors.citirideBlack,
        body: _hideVerificationContent
            ? const SizedBox.expand()
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 720;
                    final keypadGap = compact ? 16.0 : 24.0;
                    final keypadDiameter = math.min(
                      compact ? 58.0 : 72.0,
                      (constraints.maxWidth - 108) / 3,
                    );
                    final codeBoxWidth = math.min(
                      compact ? 48.0 : 52.0,
                      (constraints.maxWidth - 46 - 40) / _codeLength,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 23),
                      child: Column(
                        children: [
                          SizedBox(height: compact ? 15 : 24),
                          _EnterCodeHeader(
                            authMethod: widget.authMethod,
                            target: _isEmailAuth
                                ? _emailAddress
                                : _formattedPhoneNumber,
                            onBack: _goBack,
                          ),
                          SizedBox(height: compact ? 16 : 24),
                          _CodeBoxes(
                            code: _code,
                            result: _result,
                            boxWidth: codeBoxWidth,
                          ),
                          SizedBox(
                            height: 44,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: _result == _CodeResult.incorrect
                                  ? const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Incorrect code',
                                        style: TextStyle(
                                          color: Color(0xFFFF2727),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          height: 1,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          _CodeDeliveryActions(
                            authMethod: widget.authMethod,
                            resendSeconds: _resendSeconds,
                            isVerified: _result == _CodeResult.correct,
                            onResend: () => unawaited(_resendCode()),
                          ),
                          Expanded(
                            child: Center(
                              child: AuthNumberPad(
                                keyDiameter: keypadDiameter,
                                keyGap: keypadGap,
                                onDigitPressed: _appendDigit,
                                onBackspacePressed: _deleteLastDigit,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              onPressed: _canContinue ? _verifyCode : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.citirideYellow,
                                foregroundColor: AppColors.citirideBlack,
                                disabledBackgroundColor: const Color(
                                  0xFF918900,
                                ),
                                disabledForegroundColor: const Color(
                                  0xFF514D00,
                                ),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 18 : 25),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _EnterCodeHeader extends StatelessWidget {
  const _EnterCodeHeader({
    required this.authMethod,
    required this.target,
    required this.onBack,
  });

  final CitirideAuthMethod authMethod;
  final String target;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              tooltip: 'Back',
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                authMethod == CitirideAuthMethod.email
                    ? 'A one-time password was sent to your email'
                    : 'A verification code was sent to your Whatsapp',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              Text(
                target,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.code,
    required this.result,
    required this.boxWidth,
  });

  final String code;
  final _CodeResult result;
  final double boxWidth;

  Color get _borderColor {
    return switch (result) {
      _CodeResult.correct => const Color(0xFFAAFFBA),
      _CodeResult.incorrect => const Color(0xFFFFD6D0),
      _CodeResult.idle => AppColors.white,
    };
  }

  Color get _digitColor {
    return switch (result) {
      _CodeResult.correct => const Color(0xFF39FF14),
      _CodeResult.incorrect => const Color(0xFFFF2727),
      _CodeResult.idle => AppColors.white,
    };
  }

  String get _statusLabel {
    return switch (result) {
      _CodeResult.correct => 'Correct code',
      _CodeResult.incorrect => 'Incorrect code status',
      _CodeResult.idle => 'Verification code',
    };
  }

  String get _statusKey {
    return switch (result) {
      _CodeResult.correct => 'verification-code-correct',
      _CodeResult.incorrect => 'verification-code-incorrect',
      _CodeResult.idle => 'verification-code-idle',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey(_statusKey),
      container: true,
      label: _statusLabel,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var index = 0; index < 6; index++)
            Container(
              key: ValueKey('verification-code-box-$index'),
              width: boxWidth,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _borderColor, width: 2),
              ),
              child: Center(
                child: Text(
                  index < code.length ? code[index] : '',
                  style: TextStyle(
                    color: _digitColor,
                    fontSize: 31,
                    fontWeight: FontWeight.w400,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CodeDeliveryActions extends StatelessWidget {
  const _CodeDeliveryActions({
    required this.authMethod,
    required this.resendSeconds,
    required this.isVerified,
    required this.onResend,
  });

  final CitirideAuthMethod authMethod;
  final int resendSeconds;
  final bool isVerified;
  final VoidCallback onResend;

  bool get _canResend => isVerified || resendSeconds == 0;

  @override
  Widget build(BuildContext context) {
    final resendText = _canResend
        ? 'Resend code'
        : 'Resend code in $resendSeconds';

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          TextButton(
            onPressed: _canResend ? onResend : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white,
              disabledForegroundColor: AppColors.white,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              resendText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
          const Spacer(),
          if (authMethod == CitirideAuthMethod.phone)
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: AppColors.citirideYellow,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Send via text message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VerificationLoadingDialog extends StatelessWidget {
  const _VerificationLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Creating account',
        child: Container(
          width: 156,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: AppColors.citirideYellow,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Please wait',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignupSuccessSheet extends StatelessWidget {
  const _SignupSuccessSheet({required this.onProceed});

  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: AppColors.citirideYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.citirideBlack,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign up successful',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your account has been created successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: onProceed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.citirideYellow,
                    foregroundColor: AppColors.citirideBlack,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Proceed',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
