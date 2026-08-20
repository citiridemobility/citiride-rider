import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../auth/presentation/widgets/auth_number_pad.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_flow_widgets.dart';
import 'wallet_transaction_pin_store.dart';
import 'wallet_withdraw_request.dart';

enum _PinVisualState { idle, mismatch, matched }

/// Enter 4-digit transaction PIN, then send withdraw OTP.
class WalletWithdrawPinScreen extends StatefulWidget {
  const WalletWithdrawPinScreen({
    super.key,
    required this.request,
  });

  final WalletWithdrawRequest request;

  @override
  State<WalletWithdrawPinScreen> createState() =>
      _WalletWithdrawPinScreenState();
}

class _WalletWithdrawPinScreenState extends State<WalletWithdrawPinScreen> {
  static const _codeLength = 4;

  String _code = '';
  _PinVisualState _visualState = _PinVisualState.idle;
  bool _isSubmitting = false;

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/wallet');
  }

  void _appendDigit(String digit) {
    if (_isSubmitting) {
      return;
    }

    if (_visualState == _PinVisualState.mismatch) {
      setState(() {
        _visualState = _PinVisualState.idle;
        _code = digit;
      });
      return;
    }

    if (_code.length >= _codeLength) {
      return;
    }

    final next = _code + digit;
    setState(() {
      _visualState = _PinVisualState.idle;
      _code = next;
    });

    if (next.length == _codeLength) {
      unawaited(_submitPin(next));
    }
  }

  void _deleteLastDigit() {
    if (_isSubmitting || _code.isEmpty) {
      return;
    }

    setState(() {
      if (_visualState == _PinVisualState.mismatch) {
        _code = '';
      } else {
        _code = _code.substring(0, _code.length - 1);
      }
      _visualState = _PinVisualState.idle;
    });
  }

  Future<void> _submitPin(String pin) async {
    setState(() => _isSubmitting = true);

    try {
      final pinValid = await WalletTransactionPinStore.instance.verifyPin(pin);
      if (!pinValid) {
        if (!mounted) {
          return;
        }
        setState(() {
          _visualState = _PinVisualState.mismatch;
          _isSubmitting = false;
        });
        return;
      }

      final email = await _resolveWithdrawEmail();
      if (email == null || email.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Add your email in Personal Info before withdrawing.',
            ),
          ),
        );
        setState(() {
          _code = '';
          _visualState = _PinVisualState.idle;
          _isSubmitting = false;
        });
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() => _visualState = _PinVisualState.matched);

      await showWalletTimedLoadingDialog(
        context,
        message: 'Sending one-time password',
      );
      await CitirideAuthService().startEmailVerification(
        email: email,
        purpose: CitirideOtpPurpose.withdraw,
      );
      if (!mounted) {
        return;
      }
      context.push(
        '/wallet-withdraw-otp',
        extra: <String, Object>{
          'request': widget.request,
          'email': email,
        },
      );
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
          _code = '';
          _visualState = _PinVisualState.idle;
        });
      }
    }
  }

  Future<String?> _resolveWithdrawEmail() async {
    final profileEmail =
        RiderProfileStore.instance.profile.value.email.trim().toLowerCase();
    if (profileEmail.isNotEmpty) {
      return profileEmail;
    }

    final sessionEmail = await const CitirideSessionStore().signedInEmail();
    final cleanSession = sessionEmail?.trim().toLowerCase();
    if (cleanSession == null || cleanSession.isEmpty) {
      return null;
    }

    // Heal wiped profile email so future withdraws work offline of session.
    final profile = RiderProfileStore.instance.profile.value;
    await RiderProfileStore.instance.update(
      profile.copyWith(email: cleanSession),
    );
    return cleanSession;
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
                  children: [
                    SizedBox(height: compact ? 10 : 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _goBack,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.white,
                        ),
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
                      'Enter wallet pin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your 4 digit wallet pin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: compact ? 28 : 40),
                    _WithdrawPinBoxes(
                      code: _code,
                      visualState: _visualState,
                    ),
                    SizedBox(
                      height: 36,
                      child: _visualState == _PinVisualState.mismatch
                          ? const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Retry code',
                                  style: TextStyle(
                                    color: Color(0xFFFF2727),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            )
                          : null,
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
                    SizedBox(height: compact ? 12 : 20),
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

class _WithdrawPinBoxes extends StatelessWidget {
  const _WithdrawPinBoxes({
    required this.code,
    required this.visualState,
  });

  final String code;
  final _PinVisualState visualState;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final filled = index < code.length;
        final isLastFilled = filled && index == code.length - 1;
        final isActive = !filled &&
            index == code.length &&
            visualState == _PinVisualState.idle;

        Color borderColor = const Color(0xFF3A3A3A);
        Color fillColor = const Color(0xFF2A2A2A);

        if (visualState == _PinVisualState.mismatch && isLastFilled) {
          borderColor = const Color(0xFFFF2727);
        } else if (visualState == _PinVisualState.matched && isLastFilled) {
          borderColor = const Color(0xFF1FDC5E);
          fillColor = const Color(0xFF1FDC5E);
        } else if (isActive) {
          borderColor = AppColors.citirideYellow;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.4),
                ),
                child: Center(
                  child: filled
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                          ),
                        )
                      : isActive
                      ? const _WithdrawPinCursor()
                      : null,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _WithdrawPinCursor extends StatefulWidget {
  const _WithdrawPinCursor();

  @override
  State<_WithdrawPinCursor> createState() => _WithdrawPinCursorState();
}

class _WithdrawPinCursorState extends State<_WithdrawPinCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 22,
        color: AppColors.white,
      ),
    );
  }
}