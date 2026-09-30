import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../profile/domain/rider_profile.dart';

class EnterNumberScreen extends StatefulWidget {
  const EnterNumberScreen({
    super.key,
    this.intent = 'signup',
    this.initialEmail,
  });

  final String intent;
  final String? initialEmail;

  @override
  State<EnterNumberScreen> createState() => _EnterNumberScreenState();
}

class _EnterNumberScreenState extends State<EnterNumberScreen> {
  final _authService = CitirideAuthService();
  final _emailController = TextEditingController();

  String _email = '';
  bool _isSendingCode = false;

  bool get _hasEmail => _email.trim().isNotEmpty;

  bool get _isValidEmailAddress => _hasEmail && _isValidEmail(_email);

  bool get _showInvalidEmail => _hasEmail && !_isValidEmailAddress;

  bool get _canContinue => !_isSendingCode && _isValidEmailAddress;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmail?.trim() ?? '';
    if (initial.isNotEmpty) {
      _emailController.text = initial;
      _email = initial;
    }
    _emailController.addListener(_handleEmailChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleEmailChanged);
    _emailController.dispose();
    super.dispose();
  }

  void _handleEmailChanged() {
    setState(() {
      _email = _emailController.text;
    });
  }

  void _clearEmail() {
    if (_isSendingCode || _emailController.text.isEmpty) {
      return;
    }

    _emailController.clear();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/welcome');
  }

  Future<void> _goToEnterCode() async {
    if (!_canContinue) {
      return;
    }

    setState(() {
      _isSendingCode = true;
    });

    try {
      final email = _email.trim().toLowerCase();
      final isLogin = widget.intent == 'login';

      if (!isLogin) {
        final exists = await _authService.riderAccountExists(email: email);
        if (!mounted) {
          return;
        }
        if (exists) {
          if (mounted) {
            setState(() {
              _isSendingCode = false;
            });
          }
          await _showExistingAccountDialog(email);
          return;
        }
      }

      await _authService.startEmailVerification(
        email: email,
        purpose: isLogin
            ? CitirideOtpPurpose.login
            : CitirideOtpPurpose.signup,
      );

      final profile = RiderProfileStore.instance.profile.value;
      await RiderProfileStore.instance.update(profile.copyWith(email: email));

      if (!mounted) {
        return;
      }

      final route = Uri(
        path: '/enter-code',
        queryParameters: {
          'email': email,
          'intent': isLogin ? 'login' : 'signup',
        },
      ).toString();

      context.go(route);
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
          _isSendingCode = false;
        });
      }
    }
  }

  Future<void> _showExistingAccountDialog(String email) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          title: const Text(
            'Account already exists',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'You\'ve already signed up with this email. Log in with a code we\'ll send to your inbox.',
            style: TextStyle(color: Color(0xFFB3B3B3), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Log in',
                style: TextStyle(
                  color: AppColors.citirideYellow,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    context.go(
      Uri(
        path: '/enter-number',
        queryParameters: {
          'intent': 'login',
          'email': email,
        },
      ).toString(),
    );
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
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

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(height: compact ? 15 : 24),
                    _EnterNumberHeader(
                      isLogin: widget.intent == 'login',
                      onBack: _goBack,
                    ),
                    SizedBox(height: compact ? 18 : 24),
                    _EmailAuthInput(
                      controller: _emailController,
                      showInvalidFormat: _showInvalidEmail,
                      onClear: _clearEmail,
                      onSubmitted: () => unawaited(_goToEnterCode()),
                    ),
                    const Expanded(child: SizedBox.shrink()),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _canContinue
                            ? () => unawaited(_goToEnterCode())
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.citirideYellow,
                          foregroundColor: AppColors.citirideBlack,
                          disabledBackgroundColor: const Color(0xFF918900),
                          disabledForegroundColor: const Color(0xFF514D00),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: _isSendingCode
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.citirideBlack,
                                ),
                              )
                            : const Text(
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

class _EnterNumberHeader extends StatelessWidget {
  const _EnterNumberHeader({
    required this.onBack,
    this.isLogin = false,
  });

  final VoidCallback onBack;
  final bool isLogin;

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
                'Enter your email',
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
                isLogin
                    ? 'Log in with the one-time password we send\nto your email'
                    : 'We\'ll send you a one-time password to your\nemail address',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
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

class _EmailAuthInput extends StatelessWidget {
  const _EmailAuthInput({
    required this.controller,
    required this.showInvalidFormat,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool showInvalidFormat;
  final VoidCallback onClear;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final borderColor = showInvalidFormat
        ? const Color(0xFFFFD6D0)
        : AppColors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.only(left: 16, right: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: borderColor,
              width: showInvalidFormat ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mail_outline,
                color: Color(0xFF8F8F8F),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('auth-email-field'),
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    height: 1,
                    letterSpacing: 0,
                  ),
                  cursorColor: AppColors.citirideYellow,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: const InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isCollapsed: true,
                    hintText: 'Email address',
                    hintStyle: TextStyle(
                      color: Color(0xFF8F8F8F),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    label: 'Clear email address',
                    button: true,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E313A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 24,
          child: showInvalidFormat
              ? const Padding(
                  padding: EdgeInsets.only(left: 16, top: 7),
                  child: Text(
                    'Invalid email address',
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
      ],
    );
  }
}
