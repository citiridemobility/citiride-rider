import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../auth/presentation/widgets/auth_number_pad.dart';
import 'wallet_flow_widgets.dart';
import 'wallet_transaction_pin_store.dart';
import 'wallet_withdraw_request.dart';

enum WalletTransactionPinMode { setup, confirm, enter }

enum _PinVisualState { idle, mismatch, matched }

class WalletTransactionPinScreen extends StatefulWidget {
  const WalletTransactionPinScreen({
    super.key,
    required this.mode,
    this.pendingWithdraw,
  });

  final WalletTransactionPinMode mode;
  final WalletWithdrawRequest? pendingWithdraw;

  @override
  State<WalletTransactionPinScreen> createState() =>
      _WalletTransactionPinScreenState();
}

class _WalletTransactionPinScreenState
    extends State<WalletTransactionPinScreen> {
  static const _codeLength = 4;

  String _code = '';
  _PinVisualState _visualState = _PinVisualState.idle;
  bool _isSubmitting = false;

  String get _title {
    return switch (widget.mode) {
      WalletTransactionPinMode.setup => 'Set up your wallet pin',
      WalletTransactionPinMode.confirm => 'Confirm wallet pin',
      WalletTransactionPinMode.enter => 'Enter wallet pin',
    };
  }

  String get _subtitle {
    return switch (widget.mode) {
      WalletTransactionPinMode.setup => 'Enter a 4 digit wallet pin',
      WalletTransactionPinMode.confirm ||
      WalletTransactionPinMode.enter => 'Enter your 4 digit wallet pin',
    };
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop(false);
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
      unawaited(_handleComplete(next));
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

  Future<void> _handleComplete(String code) async {
    switch (widget.mode) {
      case WalletTransactionPinMode.setup:
        WalletTransactionPinStore.instance.setPendingPin(code);
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) {
          return;
        }
        final confirmed = await context.push<bool>(
          '/wallet-transaction-pin-confirm',
          extra: widget.pendingWithdraw,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _code = '';
          _visualState = _PinVisualState.idle;
          _isSubmitting = false;
        });
        if (confirmed == true) {
          final pendingWithdraw = widget.pendingWithdraw;
          if (pendingWithdraw != null) {
            context.pushReplacement(
              '/wallet-withdraw-pin',
              extra: pendingWithdraw,
            );
            return;
          }
          context.pop(true);
        }
        return;

      case WalletTransactionPinMode.confirm:
        final pending = WalletTransactionPinStore.instance.pendingPin;
        if (pending == null || pending != code) {
          setState(() => _visualState = _PinVisualState.mismatch);
          return;
        }

        setState(() {
          _visualState = _PinVisualState.matched;
          _isSubmitting = true;
        });

        await showWalletTimedLoadingDialog(
          context,
          message: 'Setting up wallet pin',
        );
        if (!mounted) {
          return;
        }
        await WalletTransactionPinStore.instance.savePin(code);
        if (!mounted) {
          return;
        }
        context.pop(true);
        return;

      case WalletTransactionPinMode.enter:
        if (!await WalletTransactionPinStore.instance.verifyPin(code)) {
          setState(() => _visualState = _PinVisualState.mismatch);
          return;
        }

        setState(() {
          _visualState = _PinVisualState.matched;
          _isSubmitting = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) {
          return;
        }
        context.pop(true);
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
                    _TransactionPinBoxes(
                      code: _code,
                      visualState: _visualState,
                      showCursor: widget.mode == WalletTransactionPinMode.setup &&
                          _code.length < _codeLength &&
                          _visualState == _PinVisualState.idle,
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

class _TransactionPinBoxes extends StatelessWidget {
  const _TransactionPinBoxes({
    required this.code,
    required this.visualState,
    required this.showCursor,
  });

  final String code;
  final _PinVisualState visualState;
  final bool showCursor;

  @override
  Widget build(BuildContext context) {
    final activeIndex = code.length.clamp(0, 3);

    return Row(
      children: List.generate(4, (index) {
        final filled = index < code.length;
        final isActive = showCursor && index == activeIndex;
        final isLastFilled = filled && index == code.length - 1;

        Color borderColor = const Color(0xFF3A3A3A);
        Color fillColor = const Color(0xFF2A2A2A);

        if (visualState == _PinVisualState.mismatch && isLastFilled) {
          borderColor = const Color(0xFFFF2727);
          fillColor = const Color(0xFF2A2A2A);
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
                      ? const _PinCursor()
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

class _PinCursor extends StatefulWidget {
  const _PinCursor();

  @override
  State<_PinCursor> createState() => _PinCursorState();
}

class _PinCursorState extends State<_PinCursor>
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
