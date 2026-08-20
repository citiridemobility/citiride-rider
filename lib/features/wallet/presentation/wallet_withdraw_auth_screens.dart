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
import 'wallet_withdraw_request.dart';

class WalletWithdrawOtpScreen extends StatefulWidget {
  const WalletWithdrawOtpScreen({
    super.key,
    required this.request,
    required this.email,
  });

  final WalletWithdrawRequest request;
  final String email;

  @override
  State<WalletWithdrawOtpScreen> createState() =>
      _WalletWithdrawOtpScreenState();
}

class _WalletWithdrawOtpScreenState extends State<WalletWithdrawOtpScreen> {
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
    context.go('/wallet');
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
        purpose: CitirideOtpPurpose.withdraw,
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
        setState(() => _isSubmitting = false);
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
        message: 'Verifying withdrawal',
      );
      await CitirideAuthService().confirmEmailCode(
        code: _code,
        email: widget.email,
        purpose: CitirideOtpPurpose.withdraw,
      );
      if (!mounted) {
        return;
      }
      await showWalletTimedLoadingDialog(
        context,
        message: 'Withdrawing to bank',
      );
      if (!mounted) {
        return;
      }
      context.go('/wallet-withdrawal-success');
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final isInvalid = error.isInvalidCode;
      setState(() {
        _showIncorrectError = isInvalid;
        if (isInvalid) {
          _code = '';
        }
      });
      if (!isInvalid) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _resendSeconds == 0 && !_isSubmitting;

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
              final keypadDiameter = math.min(
                74.0,
                math.max(58.0, constraints.maxWidth * 0.17),
              );
              final keypadGap = compact ? 14.0 : 18.0;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _goBack,
                        icon: const Icon(Icons.arrow_back, color: AppColors.white),
                        iconSize: 24,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 28),
                    const Text(
                      'Enter one-time password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A one-time password was sent to\n${widget.email}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PinDots(
                      filledCount: _code.length,
                      total: _codeLength,
                      hasError: _showIncorrectError,
                    ),
                    if (_showIncorrectError) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Incorrect code',
                        style: TextStyle(
                          color: Color(0xFFFF2727),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: canResend ? () => unawaited(_resendCode()) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.citirideYellow,
                        disabledForegroundColor: const Color(0xFF6B6B6B),
                      ),
                      child: Text(
                        canResend
                            ? 'Resend code'
                            : 'Resend code in $_resendSeconds',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    AuthNumberPad(
                      keyDiameter: keypadDiameter,
                      keyGap: keypadGap,
                      onDigitPressed: _appendDigit,
                      onBackspacePressed: _deleteLastDigit,
                    ),
                    const SizedBox(height: 18),
                    WalletPrimaryButton(
                      key: const ValueKey('wallet-withdraw-otp-confirm-button'),
                      label: 'Confirm withdrawal',
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

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.filledCount,
    required this.total,
    required this.hasError,
  });

  final int filledCount;
  final int total;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final filled = index < filledCount;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (hasError ? const Color(0xFFFF2727) : AppColors.citirideYellow)
                : Colors.transparent,
            border: Border.all(
              color: hasError
                  ? const Color(0xFFFF2727)
                  : filled
                      ? AppColors.citirideYellow
                      : const Color(0xFF6B6B6B),
              width: 1.4,
            ),
          ),
        );
      }),
    );
  }
}
