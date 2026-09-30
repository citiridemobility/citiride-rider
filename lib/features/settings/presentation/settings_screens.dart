import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/theme_mode_store.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../auth/presentation/widgets/auth_number_pad.dart';
import '../../profile/domain/rider_profile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return _CitirideSettingsScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 50, 14, 24),
          child: Column(
            children: [
              _SettingsHeader(title: 'Settings', onBack: _goBack),
              const SizedBox(height: 18),
              _SettingsMenuRow(
                title: 'Enable push notifications',
                trailing: Switch(
                  value: _pushNotificationsEnabled,
                  activeThumbColor: AppColors.white,
                  activeTrackColor: const Color(0xFF10D82F),
                  inactiveThumbColor: AppColors.white,
                  inactiveTrackColor: const Color(0xFF5E5E5E),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) {
                    setState(() {
                      _pushNotificationsEnabled = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 18),
              _SettingsMenuRow(
                title: 'Security',
                trailing: const _ChevronIcon(),
                onTap: () => context.push('/security'),
              ),
              const SizedBox(height: 14),
              _SettingsMenuRow(
                title: 'Theme',
                trailing: const _ChevronIcon(),
                onTap: () => _showThemePicker(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }
}

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _CitirideSettingsScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 50, 14, 24),
          child: Column(
            children: [
              _SettingsHeader(
                title: 'Security',
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                    return;
                  }

                  context.go('/settings');
                },
              ),
              const SizedBox(height: 18),
              _SettingsMenuRow(
                title: 'Change Wallet Passcode',
                subtitle: 'Update your wallet passcode',
                trailing: const _ChevronIcon(),
                onTap: () => context.push('/change-passcode'),
              ),
              const SizedBox(height: 18),
              _SettingsMenuRow(
                title: 'Reset Transaction PIN',
                subtitle: 'Setup a new transaction PIN for wallet transactions',
                trailing: const _ChevronIcon(),
                onTap: () => _sendResetOtp(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendResetOtp(BuildContext context) async {
    final email = RiderProfileStore.instance.profile.value.email.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an email to your profile before resetting PIN.'),
        ),
      );
      return;
    }

    try {
      await _showTimedLoadingDialog(context, message: 'Sending OTP');
      await CitirideAuthService().startEmailVerification(
        email: email,
        purpose: CitirideOtpPurpose.resetPin,
      );
      if (!context.mounted) {
        return;
      }
      context.push('/reset-pin-otp');
    } on CitirideAuthException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class ChangePasscodeScreen extends StatefulWidget {
  const ChangePasscodeScreen({super.key});

  @override
  State<ChangePasscodeScreen> createState() => _ChangePasscodeScreenState();
}

class _ChangePasscodeScreenState extends State<ChangePasscodeScreen> {
  final _oldPasscodeController = TextEditingController();
  final _newPasscodeController = TextEditingController();

  bool get _canSave {
    return _oldPasscodeController.text.trim().isNotEmpty &&
        _newPasscodeController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _oldPasscodeController.addListener(_onFieldChanged);
    _newPasscodeController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _oldPasscodeController.dispose();
    _newPasscodeController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    setState(() {});
  }

  Future<void> _saveChanges() async {
    if (!_canSave) {
      return;
    }

    await _showTimedLoadingDialog(context);
    if (!mounted) {
      return;
    }

    await _showSuccessSheet(
      context,
      title: 'Passcode changed successfully',
      message: 'Your wallet passcode has been updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CitirideSettingsScaffold(
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsHeader(
                      title: 'Change Passcode',
                      onBack: () {
                        if (context.canPop()) {
                          context.pop();
                          return;
                        }

                        context.go('/security');
                      },
                    ),
                    const SizedBox(height: 20),
                    const _FormLabel('Old passcode'),
                    const SizedBox(height: 10),
                    _SecureNumberField(
                      key: const ValueKey('old-passcode-field'),
                      controller: _oldPasscodeController,
                      hintText: 'Enter old passcode',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    const _FormLabel('New passcode'),
                    const SizedBox(height: 10),
                    _SecureNumberField(
                      key: const ValueKey('new-passcode-field'),
                      controller: _newPasscodeController,
                      hintText: 'Enter new passcode',
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),
            _BottomPrimaryButton(
              key: const ValueKey('change-passcode-save-button'),
              label: 'Save changes',
              enabled: _canSave,
              onPressed: _saveChanges,
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPinOtpScreen extends StatefulWidget {
  const ResetPinOtpScreen({super.key});

  @override
  State<ResetPinOtpScreen> createState() => _ResetPinOtpScreenState();
}

enum _ResetOtpResult { idle, correct, incorrect }

class _ResetPinOtpScreenState extends State<ResetPinOtpScreen> {
  static const _codeLength = 6;
  static const _resendStartSeconds = 40;

  String _code = '';
  int _resendSeconds = _resendStartSeconds;
  Timer? _resendTimer;
  _ResetOtpResult _result = _ResetOtpResult.idle;
  bool _isSubmitting = false;

  bool get _isComplete => _code.length == _codeLength;

  bool get _canContinue {
    return _isComplete &&
        _result != _ResetOtpResult.incorrect &&
        !_isSubmitting;
  }

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
      _result = _ResetOtpResult.idle;
      _code += digit;
    });
  }

  void _deleteLastDigit() {
    if (_isSubmitting || _code.isEmpty) {
      return;
    }

    setState(() {
      _result = _ResetOtpResult.idle;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0 || _isSubmitting) {
      return;
    }

    final email = RiderProfileStore.instance.profile.value.email.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email found on your profile.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await CitirideAuthService().startEmailVerification(
        email: email,
        purpose: CitirideOtpPurpose.resetPin,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _code = '';
        _result = _ResetOtpResult.idle;
        _resendSeconds = _resendStartSeconds;
        _isSubmitting = false;
      });
      _startResendCountdown();
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _verifyCode() async {
    if (!_canContinue) {
      return;
    }

    final email = RiderProfileStore.instance.profile.value.email.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email found on your profile.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _result = _ResetOtpResult.idle;
    });

    try {
      await CitirideAuthService().confirmEmailCode(
        code: _code,
        email: email,
        purpose: CitirideOtpPurpose.resetPin,
      );
    } on CitirideAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _result = error.isInvalidCode
            ? _ResetOtpResult.incorrect
            : _ResetOtpResult.idle;
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
      _result = _ResetOtpResult.correct;
    });

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) {
      return;
    }

    context.push('/reset-pin-new');
  }

  @override
  Widget build(BuildContext context) {
    final profile = RiderProfileStore.instance.profile.value;

    return _CitirideSettingsScaffold(
      child: SafeArea(
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
                  _ResetPinHeader(
                    title: 'Reset PIN',
                    target: profile.email.isNotEmpty
                        ? profile.email
                        : profile.phoneNumber,
                    onBack: () {
                      if (context.canPop()) {
                        context.pop();
                        return;
                      }

                      context.go('/security');
                    },
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  _ResetOtpBoxes(
                    code: _code,
                    result: _result,
                    boxWidth: codeBoxWidth,
                  ),
                  SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _result == _ResetOtpResult.incorrect
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
                  _ResetCodeActions(
                    resendSeconds: _resendSeconds,
                    onResend: _resendCode,
                    onTryDifferentMethod: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'A different reset method will be available soon.',
                          ),
                        ),
                      );
                    },
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
                  _BottomPrimaryButton(
                    key: const ValueKey('reset-pin-otp-continue-button'),
                    label: 'Continue',
                    enabled: _canContinue,
                    onPressed: _verifyCode,
                    includeSafeAreaBottom: false,
                  ),
                  SizedBox(height: compact ? 18 : 25),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ResetPinNewPinScreen extends StatefulWidget {
  const ResetPinNewPinScreen({super.key});

  @override
  State<ResetPinNewPinScreen> createState() => _ResetPinNewPinScreenState();
}

class _ResetPinNewPinScreenState extends State<ResetPinNewPinScreen> {
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool get _hasMismatch {
    return _newPinController.text.isNotEmpty &&
        _confirmPinController.text.isNotEmpty &&
        _newPinController.text != _confirmPinController.text;
  }

  bool get _canSave {
    return _newPinController.text.trim().isNotEmpty &&
        _confirmPinController.text.trim().isNotEmpty &&
        !_hasMismatch;
  }

  @override
  void initState() {
    super.initState();
    _newPinController.addListener(_onFieldChanged);
    _confirmPinController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    setState(() {});
  }

  Future<void> _saveChanges() async {
    if (!_canSave) {
      return;
    }

    await _showTimedLoadingDialog(context);
    if (!mounted) {
      return;
    }

    await _showSuccessSheet(
      context,
      title: 'Transaction PIN reset successfully',
      message: 'Your transaction PIN is ready for wallet payments.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CitirideSettingsScaffold(
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsHeader(
                      title: 'Reset PIN',
                      onBack: () {
                        if (context.canPop()) {
                          context.pop();
                          return;
                        }

                        context.go('/security');
                      },
                    ),
                    const SizedBox(height: 20),
                    const _FormLabel('New PIN'),
                    const SizedBox(height: 10),
                    _SecureNumberField(
                      key: const ValueKey('new-transaction-pin-field'),
                      controller: _newPinController,
                      hintText: 'Enter new PIN',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    const _FormLabel('Confirm PIN'),
                    const SizedBox(height: 10),
                    _SecureNumberField(
                      key: const ValueKey('confirm-transaction-pin-field'),
                      controller: _confirmPinController,
                      hintText: 'Confirm new PIN',
                      textInputAction: TextInputAction.done,
                    ),
                    if (_hasMismatch) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'PINs do not match',
                        style: TextStyle(
                          color: Color(0xFFFF2727),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _BottomPrimaryButton(
              key: const ValueKey('reset-pin-new-save-button'),
              label: 'Save changes',
              enabled: _canSave,
              onPressed: _saveChanges,
            ),
          ],
        ),
      ),
    );
  }
}

class _CitirideSettingsScaffold extends StatelessWidget {
  const _CitirideSettingsScaffold({
    required this.child,
    this.resizeToAvoidBottomInset = false,
  });

  final Widget child;
  final bool resizeToAvoidBottomInset;

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
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: AppColors.citirideBlack,
        body: child,
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              tooltip: 'Back',
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2B2B2B),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: subtitle == null ? 51 : 72,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronIcon extends StatelessWidget {
  const _ChevronIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_right, color: Color(0xFFB8B8B8), size: 28);
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

class _SecureNumberField extends StatelessWidget {
  const _SecureNumberField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.textInputAction,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.white, width: 2),
      ),
      child: TextField(
        controller: controller,
        cursorColor: AppColors.citirideYellow,
        keyboardType: TextInputType.number,
        textInputAction: textInputAction,
        obscureText: true,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF737373),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
          filled: false,
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          counterText: '',
        ),
      ),
    );
  }
}

class _BottomPrimaryButton extends StatelessWidget {
  const _BottomPrimaryButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.includeSafeAreaBottom = true,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool includeSafeAreaBottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        (includeSafeAreaBottom ? MediaQuery.paddingOf(context).bottom : 0) + 48,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.citirideYellow,
            disabledBackgroundColor: const Color(0xFF918B00),
            foregroundColor: AppColors.citirideBlack,
            disabledForegroundColor: AppColors.citirideBlack.withValues(
              alpha: 0.66,
            ),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetPinHeader extends StatelessWidget {
  const _ResetPinHeader({
    required this.title,
    required this.target,
    required this.onBack,
  });

  final String title;
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
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'A PIN reset code was sent to your Whatsapp',
                textAlign: TextAlign.center,
                style: TextStyle(
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

class _ResetOtpBoxes extends StatelessWidget {
  const _ResetOtpBoxes({
    required this.code,
    required this.result,
    required this.boxWidth,
  });

  final String code;
  final _ResetOtpResult result;
  final double boxWidth;

  Color get _borderColor {
    return switch (result) {
      _ResetOtpResult.correct => const Color(0xFFAAFFBA),
      _ResetOtpResult.incorrect => const Color(0xFFFFD6D0),
      _ResetOtpResult.idle => AppColors.white,
    };
  }

  Color get _digitColor {
    return switch (result) {
      _ResetOtpResult.correct => const Color(0xFF39FF14),
      _ResetOtpResult.incorrect => const Color(0xFFFF2727),
      _ResetOtpResult.idle => AppColors.white,
    };
  }

  String get _statusKey {
    return switch (result) {
      _ResetOtpResult.correct => 'reset-pin-code-correct',
      _ResetOtpResult.incorrect => 'reset-pin-code-incorrect',
      _ResetOtpResult.idle => 'reset-pin-code-idle',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey(_statusKey),
      container: true,
      label: 'Reset PIN code',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var index = 0; index < 6; index++)
            Container(
              key: ValueKey('reset-pin-code-box-$index'),
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

class _ResetCodeActions extends StatelessWidget {
  const _ResetCodeActions({
    required this.resendSeconds,
    required this.onResend,
    required this.onTryDifferentMethod,
  });

  final int resendSeconds;
  final VoidCallback onResend;
  final VoidCallback onTryDifferentMethod;

  @override
  Widget build(BuildContext context) {
    final canResend = resendSeconds == 0;
    final resendText = canResend
        ? 'Resend code'
        : 'Resend code in $resendSeconds';

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          TextButton(
            onPressed: canResend ? onResend : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white,
              disabledForegroundColor: const Color(0xFF8F8F8F),
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
          TextButton(
            onPressed: onTryDifferentMethod,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.citirideYellow,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Try a different method',
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

Future<void> _showThemePicker(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Theme options',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _ThemePickerOverlay(
        onClose: () => Navigator.of(dialogContext).pop(),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ThemePickerOverlay extends StatelessWidget {
  const _ThemePickerOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.68)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Material(
                  color: AppColors.citirideBlack,
                  borderRadius: BorderRadius.circular(25),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: ValueListenableBuilder<ThemeMode>(
                      valueListenable: CitirideThemeModeStore.instance.mode,
                      builder: (context, mode, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Theme',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ThemeOptionTile(
                              label: 'System',
                              selected: mode == ThemeMode.system,
                              onTap: () {
                                CitirideThemeModeStore.instance.update(
                                  ThemeMode.system,
                                );
                                onClose();
                              },
                            ),
                            _ThemeOptionTile(
                              label: 'Dark',
                              selected: mode == ThemeMode.dark,
                              onTap: () {
                                CitirideThemeModeStore.instance.update(
                                  ThemeMode.dark,
                                );
                                onClose();
                              },
                            ),
                            _ThemeOptionTile(
                              label: 'Light',
                              selected: mode == ThemeMode.light,
                              onTap: () {
                                CitirideThemeModeStore.instance.update(
                                  ThemeMode.light,
                                );
                                onClose();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.toggle_on : Icons.toggle_off,
                color: selected
                    ? AppColors.citirideYellow
                    : const Color(0xFF777777),
                size: 40,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showTimedLoadingDialog(
  BuildContext context, {
  String message = 'Please wait',
}) async {
  var dialogVisible = true;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (dialogContext) {
        return _SettingsLoadingDialog(message: message);
      },
    ).whenComplete(() {
      dialogVisible = false;
    }),
  );

  await Future<void>.delayed(const Duration(seconds: 2));
  if (!context.mounted || !dialogVisible) {
    return;
  }

  dialogVisible = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
}

class _SettingsLoadingDialog extends StatelessWidget {
  const _SettingsLoadingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: message,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: AppColors.citirideYellow,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
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

Future<void> _showSuccessSheet(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.74),
    builder: (sheetContext) {
      return _SettingsSuccessSheet(
        title: title,
        message: message,
        onDone: () {
          final navigator = Navigator.of(sheetContext, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
          }

          if (context.mounted) {
            context.go('/security');
          }
        },
      );
    },
  );
}

class _SettingsSuccessSheet extends StatelessWidget {
  const _SettingsSuccessSheet({
    required this.title,
    required this.message,
    required this.onDone,
  });

  final String title;
  final String message;
  final VoidCallback onDone;

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
              const _AnimatedSuccessCheck(),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
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
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.citirideYellow,
                    foregroundColor: AppColors.citirideBlack,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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

class _AnimatedSuccessCheck extends StatefulWidget {
  const _AnimatedSuccessCheck();

  @override
  State<_AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<_AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 86,
        height: 86,
        decoration: const BoxDecoration(
          color: Color(0xFF1FDC5E),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: AppColors.white, size: 48),
      ),
    );
  }
}
