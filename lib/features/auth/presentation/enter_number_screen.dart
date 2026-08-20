import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../profile/domain/rider_profile.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import 'widgets/auth_number_pad.dart';

class EnterNumberScreen extends StatefulWidget {
  const EnterNumberScreen({super.key});

  @override
  State<EnterNumberScreen> createState() => _EnterNumberScreenState();
}

enum _AuthEntryMode { phone, email }

class _EnterNumberScreenState extends State<EnterNumberScreen> {
  static const _maxDigits = 13;

  final _authService = CitirideAuthService();
  final _emailController = TextEditingController();

  String _digits = '';
  String _email = '';
  _AuthEntryMode _entryMode = _AuthEntryMode.email;
  bool _isSendingCode = false;

  bool get _isPhoneAuth => _entryMode == _AuthEntryMode.phone;

  bool get _isEmailAuth => _entryMode == _AuthEntryMode.email;

  bool get _isValidNumber => _isValidNigerianMobileNumber(_digits);

  bool get _hasEmail => _email.trim().isNotEmpty;

  bool get _isValidEmailAddress => _hasEmail && _isValidEmail(_email);

  bool get _showInvalidEmail =>
      _isEmailAuth && _hasEmail && !_isValidEmailAddress;

  bool get _canContinue {
    if (_isSendingCode) {
      return false;
    }

    return _isPhoneAuth ? _isValidNumber : _isValidEmailAddress;
  }

  bool get _showInvalidFormat =>
      _isPhoneAuth && _digits.length >= 10 && !_isValidNumber;

  @override
  void initState() {
    super.initState();
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

  void _appendDigit(String digit) {
    if (_isSendingCode || _digits.length >= _maxDigits || !_isPhoneAuth) {
      return;
    }

    setState(() {
      _digits += digit;
    });
  }

  void _deleteLastDigit() {
    if (_isSendingCode || _digits.isEmpty || !_isPhoneAuth) {
      return;
    }

    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _clearDigits() {
    if (_isSendingCode || _digits.isEmpty) {
      return;
    }

    setState(() {
      _digits = '';
    });
  }

  void _clearEmail() {
    if (_isSendingCode || _emailController.text.isEmpty) {
      return;
    }

    _emailController.clear();
  }

  void _switchToEmail() {
    FocusScope.of(context).unfocus();
    setState(() {
      _entryMode = _AuthEntryMode.email;
    });
  }

  void _switchToPhone() {
    FocusScope.of(context).unfocus();
    setState(() {
      _entryMode = _AuthEntryMode.phone;
    });
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
      if (_isPhoneAuth) {
        // Phone is contact info only — save it, then continue with email OTP.
        final phoneNumber = _toNigerianE164(_digits);
        final profile = RiderProfileStore.instance.profile.value;
        await RiderProfileStore.instance.update(
          profile.copyWith(phoneNumber: phoneNumber),
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _entryMode = _AuthEntryMode.email;
          _isSendingCode = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone number saved. Continue with email verification.',
            ),
          ),
        );
        return;
      }

      final email = _email.trim().toLowerCase();
      await _authService.startEmailVerification(email: email);

      final profile = RiderProfileStore.instance.profile.value;
      await RiderProfileStore.instance.update(profile.copyWith(email: email));

      if (!mounted) {
        return;
      }

      final route = Uri(
        path: '/enter-code',
        queryParameters: {
          'authMethod': CitirideAuthMethod.email.name,
          'email': email,
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

  static bool _isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
  }

  static String _toNigerianE164(String digits) {
    final normalized = digits.length == 11 && digits.startsWith('0')
        ? digits.substring(1)
        : digits;
    return '+234$normalized';
  }

  static bool _isValidNigerianMobileNumber(String digits) {
    final normalized = digits.length == 11 && digits.startsWith('0')
        ? digits.substring(1)
        : digits;

    return RegExp(r'^(70|80|81|90|91)\d{8}$').hasMatch(normalized);
  }

  static String _formatDigits(String digits) {
    if (digits.length <= 3) {
      return digits;
    }

    if (digits.length <= 7) {
      return '${digits.substring(0, 3)} ${digits.substring(3)}';
    }

    return '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}';
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
                    SizedBox(height: compact ? 15 : 24),
                    _EnterNumberHeader(entryMode: _entryMode, onBack: _goBack),
                    SizedBox(height: compact ? 18 : 24),
                    if (_isPhoneAuth) ...[
                      _PhoneNumberInput(
                        digits: _digits,
                        formattedNumber: _formatDigits(_digits),
                        showInvalidFormat: _showInvalidFormat,
                        onClear: _clearDigits,
                      ),
                      SizedBox(height: compact ? 8 : 11),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.white,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Send via text message instead',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
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
                      SizedBox(
                        height: 34,
                        child: TextButton(
                          key: const ValueKey('use-email-instead'),
                          onPressed: _isSendingCode ? null : _switchToEmail,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.citirideYellow,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Use email instead',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                    ] else ...[
                      _EmailAuthInput(
                        controller: _emailController,
                        showInvalidFormat: _showInvalidEmail,
                        onClear: _clearEmail,
                        onSubmitted: () => unawaited(_goToEnterCode()),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('use-phone-instead'),
                          onPressed: _isSendingCode ? null : _switchToPhone,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.citirideYellow,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Use phone number instead',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                      SizedBox(height: compact ? 12 : 18),
                    ],
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
                            : Text(
                                _isPhoneAuth ? 'Save phone number' : 'Continue',
                                style: const TextStyle(
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
  const _EnterNumberHeader({required this.entryMode, required this.onBack});

  final _AuthEntryMode entryMode;
  final VoidCallback onBack;

  bool get _isEmailAuth => entryMode == _AuthEntryMode.email;

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
                _isEmailAuth ? 'Enter your email' : 'Enter your number',
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
              Text(
                _isEmailAuth
                    ? 'We\'ll send you a one-time password to your\nemail address'
                    : 'We\'ll send you a verification code on your\nWhatsapp',
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

class _PhoneNumberInput extends StatelessWidget {
  const _PhoneNumberInput({
    required this.digits,
    required this.formattedNumber,
    required this.showInvalidFormat,
    required this.onClear,
  });

  final String digits;
  final String formattedNumber;
  final bool showInvalidFormat;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final borderColor = showInvalidFormat
        ? const Color(0xFFFFD6D0)
        : AppColors.white;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _NigeriaCountryPill(),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.only(left: 16, right: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: borderColor,
                    width: showInvalidFormat ? 3 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        digits.isEmpty ? '123 4567 890' : formattedNumber,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: digits.isEmpty
                              ? const Color(0xFF8F8F8F)
                              : AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (digits.isNotEmpty)
                      GestureDetector(
                        onTap: onClear,
                        behavior: HitTestBehavior.opaque,
                        child: Semantics(
                          label: 'Clear phone number',
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
                        padding: EdgeInsets.only(left: 1, top: 7),
                        child: Text(
                          'Invalid number format',
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
          ),
        ),
      ],
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

class _NigeriaCountryPill extends StatelessWidget {
  const _NigeriaCountryPill();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Nigeria country code',
      child: Container(
        width: 90,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.white),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 18,
            child: CompatibleSvgPicture.asset(
              'assets/images/Nigerian flag.svg',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
