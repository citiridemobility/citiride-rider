import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../auth/presentation/widgets/auth_number_pad.dart';
import 'wallet_flow_widgets.dart';

enum WalletPasscodeMode { setup, confirm, unlock }

enum _PasscodeVisualState { idle, mismatch, matched }

class WalletPasscodeScreen extends StatefulWidget {
  const WalletPasscodeScreen({
    super.key,
    required this.mode,
  });

  final WalletPasscodeMode mode;

  @override
  State<WalletPasscodeScreen> createState() => _WalletPasscodeScreenState();
}

class _WalletPasscodeScreenState extends State<WalletPasscodeScreen> {
  static const _codeLength = 6;

  String _code = '';
  _PasscodeVisualState _visualState = _PasscodeVisualState.idle;
  bool _isSubmitting = false;

  String get _title {
    return switch (widget.mode) {
      WalletPasscodeMode.setup => 'Set up your passcode',
      WalletPasscodeMode.confirm => 'Confirm passcode',
      WalletPasscodeMode.unlock => 'Enter Passcode',
    };
  }

  String get _subtitle {
    return switch (widget.mode) {
      WalletPasscodeMode.setup => 'Enter a 6 digit passcode',
      WalletPasscodeMode.confirm ||
      WalletPasscodeMode.unlock => 'Enter your 6 digit passcode',
    };
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    if (widget.mode == WalletPasscodeMode.unlock) {
      context.go('/home');
      return;
    }

    context.go('/wallet-terms');
  }

  void _appendDigit(String digit) {
    if (_isSubmitting) {
      return;
    }

    if (_visualState == _PasscodeVisualState.mismatch) {
      setState(() {
        _visualState = _PasscodeVisualState.idle;
        _code = digit;
      });
      return;
    }

    if (_code.length >= _codeLength) {
      return;
    }

    final next = _code + digit;
    setState(() {
      _visualState = _PasscodeVisualState.idle;
      _code = next;
    });

    if (next.length == _codeLength) {
      _handleComplete(next);
    }
  }

  void _deleteLastDigit() {
    if (_isSubmitting || _code.isEmpty) {
      return;
    }

    setState(() {
      if (_visualState == _PasscodeVisualState.mismatch) {
        _code = '';
      } else {
        _code = _code.substring(0, _code.length - 1);
      }
      _visualState = _PasscodeVisualState.idle;
    });
  }

  Future<void> _handleComplete(String code) async {
    switch (widget.mode) {
      case WalletPasscodeMode.setup:
        await WalletEnrollmentStore.instance.setPendingPasscode(code);
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) {
          return;
        }
        context.push('/wallet-confirm-passcode');
        setState(() {
          _code = '';
          _visualState = _PasscodeVisualState.idle;
        });
        return;

      case WalletPasscodeMode.confirm:
        final pending = WalletEnrollmentStore.instance.pendingPasscode;
        if (pending == null || pending != code) {
          setState(() {
            _visualState = _PasscodeVisualState.mismatch;
          });
          return;
        }

        setState(() {
          _visualState = _PasscodeVisualState.matched;
          _isSubmitting = true;
        });
        await showWalletTimedLoadingDialog(
          context,
          message: 'Setting up your wallet',
        );
        if (!mounted) {
          return;
        }
        await WalletEnrollmentStore.instance.completeEnrollment(code);
        if (!mounted) {
          return;
        }
        context.go('/wallet');
        return;

      case WalletPasscodeMode.unlock:
        if (!await WalletEnrollmentStore.instance.verifyPasscode(code)) {
          setState(() {
            _visualState = _PasscodeVisualState.mismatch;
          });
          return;
        }

        setState(() {
          _visualState = _PasscodeVisualState.matched;
          _isSubmitting = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) {
          return;
        }
        context.go('/wallet');
        return;
    }
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
                        tooltip: 'Back',
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 28),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: compact ? 28 : 40),
                    _PasscodeBoxes(
                      code: _code,
                      visualState: _visualState,
                      showCursor: widget.mode == WalletPasscodeMode.setup &&
                          _code.length < _codeLength &&
                          _visualState == _PasscodeVisualState.idle,
                    ),
                    SizedBox(
                      height: 36,
                      child: _visualState == _PasscodeVisualState.mismatch
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

class _PasscodeBoxes extends StatelessWidget {
  const _PasscodeBoxes({
    required this.code,
    required this.visualState,
    required this.showCursor,
  });

  final String code;
  final _PasscodeVisualState visualState;
  final bool showCursor;

  @override
  Widget build(BuildContext context) {
    final activeIndex = code.length.clamp(0, 5);

    return Row(
      children: List.generate(6, (index) {
        final filled = index < code.length;
        final isActive = showCursor && index == activeIndex;
        final isLastFilled = filled && index == code.length - 1;

        Color borderColor = const Color(0xFF3A3A3A);
        Color fillColor = const Color(0xFF2A2A2A);

        if (visualState == _PasscodeVisualState.mismatch && isLastFilled) {
          borderColor = const Color(0xFFFF2727);
          fillColor = const Color(0xFF4A1515);
        } else if (visualState == _PasscodeVisualState.matched && isLastFilled) {
          borderColor = const Color(0xFF1FDC5E);
        } else if (isActive) {
          borderColor = AppColors.citirideYellow;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
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
                      ? const _PasscodeCursor()
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

class _PasscodeCursor extends StatefulWidget {
  const _PasscodeCursor();

  @override
  State<_PasscodeCursor> createState() => _PasscodeCursorState();
}

class _PasscodeCursorState extends State<_PasscodeCursor>
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
