import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_otp_client.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_flow_widgets.dart';

class WalletEmailScreen extends StatefulWidget {
  const WalletEmailScreen({super.key});

  @override
  State<WalletEmailScreen> createState() => _WalletEmailScreenState();
}

class _WalletEmailScreenState extends State<WalletEmailScreen> {
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();

  String _email = '';
  bool _isSending = false;

  bool get _isValidEmail => _validateEmail(_email);

  bool get _canContinue => _isValidEmail && !_isSending;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleEmailChanged);
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _handleEmailChanged() {
    final next = _emailController.text.trim();
    if (next == _email) {
      return;
    }

    setState(() {
      _email = next;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet-phone-number');
  }

  Future<void> _onNext() async {
    if (!_canContinue) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSending = true;
    });

    final email = _email.trim().toLowerCase();

    try {
      await showWalletTimedLoadingDialog(
        context,
        message: 'Sending OTP',
      );

      await CitirideAuthService().startEmailVerification(
        email: email,
        purpose: CitirideOtpPurpose.wallet,
      );

      final profile = RiderProfileStore.instance.profile.value;
      await RiderProfileStore.instance.update(profile.copyWith(email: email));

      if (!mounted) {
        return;
      }

      final route = Uri(
        path: '/wallet-verify-email',
        queryParameters: {'email': email},
      ).toString();
      context.push(route);
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
          _isSending = false;
        });
      }
    }
  }

  static bool _validateEmail(String email) {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                WalletFlowTopBar(onBack: _goBack),
                const SizedBox(height: 16),
                const WalletProgressBar(progress: 0.25),
                const SizedBox(height: 28),
                const Text(
                  'What’s Your Email Address',
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
                  'Enter the email you want associated with this account',
                  style: TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 28),
                ListenableBuilder(
                  listenable: _emailFocusNode,
                  builder: (context, _) {
                    return _EmailInputField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      focused: _emailFocusNode.hasFocus,
                      onSubmitted: () => unawaited(_onNext()),
                    );
                  },
                ),
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: _InfoBadge(),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A verification code will be sent to this email, make sure to enter it in the next screen',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                WalletPrimaryButton(
                  key: const ValueKey('wallet-email-next-button'),
                  label: 'Next',
                  enabled: _canContinue,
                  onPressed: () => unawaited(_onNext()),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _EmailInputField extends StatelessWidget {
  const _EmailInputField({
    required this.controller,
    required this.focusNode,
    required this.focused,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool focused;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? AppColors.citirideYellow : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline_rounded,
            color: Color(0xFF8F8F8F),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('wallet-email-field'),
              controller: controller,
              focusNode: focusNode,
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
                hintText: 'Email Address',
                hintStyle: TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
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
