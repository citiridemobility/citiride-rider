import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../auth/presentation/widgets/auth_number_pad.dart';
import 'wallet_flow_widgets.dart';

class WalletVerifyEmailScreen extends StatefulWidget {
  const WalletVerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<WalletVerifyEmailScreen> createState() =>
      _WalletVerifyEmailScreenState();
}

class _WalletVerifyEmailScreenState extends State<WalletVerifyEmailScreen> {
  static const _codeLength = 6;
  static const _resendStartSeconds = 30;

  String _code = '';
  int _resendSeconds = _resendStartSeconds;
  Timer? _resendTimer;
  bool _showIncorrectError = false;
  bool _isSubmitting = false;

  bool get _isComplete => _code.length == _codeLength;

  bool get _canConfirm => _isComplete && !_isSubmitting;

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
        setState(() => _resendSeconds = 0);
        timer.cancel();
        return;
      }

      setState(() => _resendSeconds -= 1);
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet-email');
  }

  void _appendDigit(String digit) {
    if (_isSubmitting || _code.length >= _codeLength) {
      return;
    }

    setState(() {
      _showIncorrectError = false;
      _code += digit;
    });
  }

  void _deleteLastDigit() {
    if (_isSubmitting || _code.isEmpty) {
      return;
    }

    setState(() {
      _showIncorrectError = false;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _resendCode() async {
    if (_isSubmitting || _resendSeconds > 0) {
      return;
    }

    setState(() {
      _code = '';
      _showIncorrectError = false;
      _isSubmitting = true;
    });

    try {
      await showWalletTimedLoadingDialog(
        context,
        message: 'Sending OTP',
      );
      await CitirideAuthService().startEmailVerification(
        email: widget.email,
        purpose: CitirideOtpPurpose.wallet,
      );
      if (!mounted) {
        return;
      }
      setState(() => _resendSeconds = _resendStartSeconds);
      _startResendCountdown();
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _confirmCode() async {
    if (!_canConfirm) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _showIncorrectError = false;
    });

    try {
      await showWalletTimedLoadingDialog(
        context,
        message: 'Verifying email address',
      );
      await CitirideAuthService().confirmEmailCode(
        code: _code,
        email: widget.email,
        purpose: CitirideOtpPurpose.wallet,
      );
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _showIncorrectError = error.isInvalidCode;
      });
      if (!error.isInvalidCode) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    await _showVerifiedSheet();
  }

  Future<void> _showVerifiedSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (sheetContext) {
        return _EmailVerifiedSuccessSheet(
          onContinue: () {
            final navigator = Navigator.of(sheetContext, rootNavigator: true);
            if (navigator.canPop()) {
              navigator.pop();
            }

            if (context.mounted) {
              context.push('/wallet-terms');
            }
          },
        );
      },
    );
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final keypadGap = compact ? 16.0 : 24.0;
              final keypadDiameter = math.min(
                compact ? 58.0 : 72.0,
                (constraints.maxWidth - 108) / 3,
              );

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: compact ? 10 : 12),
                    WalletFlowTopBar(onBack: _goBack),
                    SizedBox(height: compact ? 12 : 16),
                    const WalletProgressBar(progress: 0.5),
                    SizedBox(height: compact ? 20 : 28),
                    const Text(
                      'Verify Your Email Address',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We’ve sent a 6 digit code to your email. Check your inbox or spam folder and enter it here.',
                      style: TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    _WalletEmailOtpBoxes(
                      code: _code,
                      hasError: _showIncorrectError,
                    ),
                    SizedBox(
                      height: 28,
                      child: _showIncorrectError
                          ? const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Incorrect code. Please try again.',
                                style: TextStyle(
                                  color: Color(0xFFFF2727),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0,
                                ),
                              ),
                            )
                          : null,
                    ),
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: AppColors.citirideYellow,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '!',
                              style: TextStyle(
                                color: AppColors.citirideBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Didn’t get the code?',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: (_isSubmitting || _resendSeconds > 0)
                              ? null
                              : () => unawaited(_resendCode()),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.citirideYellow,
                            disabledForegroundColor: const Color(0xFF6B6B6B),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _resendSeconds > 0
                                ? 'Resend in $_resendSeconds'
                                : 'Resend',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth - 40,
                            child: AuthNumberPad(
                              keyDiameter: keypadDiameter,
                              keyGap: keypadGap,
                              onDigitPressed: _appendDigit,
                              onBackspacePressed: _deleteLastDigit,
                            ),
                          ),
                        ),
                      ),
                    ),
                    WalletPrimaryButton(
                      key: const ValueKey('wallet-verify-email-confirm-button'),
                      label: 'Confirm',
                      enabled: _canConfirm,
                      onPressed: () => unawaited(_confirmCode()),
                    ),
                    SizedBox(height: compact ? 18 : 28),
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

class _WalletEmailOtpBoxes extends StatelessWidget {
  const _WalletEmailOtpBoxes({
    required this.code,
    required this.hasError,
  });

  final String code;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(6, (index) {
        final hasDigit = index < code.length;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasError
                        ? const Color(0xFFFF2727)
                        : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    hasDigit ? code[index] : '',
                    style: TextStyle(
                      color: hasError
                          ? const Color(0xFFFF2727)
                          : AppColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _EmailVerifiedSuccessSheet extends StatelessWidget {
  const _EmailVerifiedSuccessSheet({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
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
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFF1FDC5E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Email verified successfully',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your email has been verified. Continue to finish setting up your wallet.',
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
              WalletPrimaryButton(
                key: const ValueKey('wallet-email-verified-continue-button'),
                label: 'Continue',
                enabled: true,
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
