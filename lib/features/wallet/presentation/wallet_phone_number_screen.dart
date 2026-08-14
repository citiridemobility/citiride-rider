import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_flow_widgets.dart';

class WalletPhoneNumberScreen extends StatefulWidget {
  const WalletPhoneNumberScreen({super.key});

  @override
  State<WalletPhoneNumberScreen> createState() =>
      _WalletPhoneNumberScreenState();
}

class _WalletPhoneNumberScreenState extends State<WalletPhoneNumberScreen> {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  String _digits = '';
  bool _isSending = false;

  bool get _isValidNumber => _isValidNigerianMobileNumber(_digits);

  bool get _canContinue => _isValidNumber && !_isSending;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_handlePhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_handlePhoneChanged);
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _handlePhoneChanged() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits == _digits) {
      return;
    }

    setState(() {
      _digits = digits;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet-get-started');
  }

  Future<void> _onNext() async {
    if (!_canContinue) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSending = true;
    });

    final phoneNumber = _toNigerianE164(_digits);
    final profile = RiderProfileStore.instance.profile.value;
    await RiderProfileStore.instance.update(
      profile.copyWith(phoneNumber: phoneNumber),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
    });

    // Phone is contact info only — email OTP is the verification step.
    context.push('/wallet-email');
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
                  'What’s Your Phone Number?',
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
                  'Enter the phone number you want to use for this account.',
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
                  listenable: _phoneFocusNode,
                  builder: (context, _) {
                    return _PhoneNumberField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      focused: _phoneFocusNode.hasFocus,
                      onSubmitted: () => unawaited(_onNext()),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _UseEmailInsteadRow(
                  onTap: () => context.push('/wallet-email'),
                ),
                const Spacer(),
                WalletPrimaryButton(
                  key: const ValueKey('wallet-phone-next-button'),
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

class _PhoneNumberField extends StatelessWidget {
  const _PhoneNumberField({
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? AppColors.citirideYellow : const Color(0xFF918900),
        ),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CompatibleSvgPicture.asset(
                'assets/images/Nigerian flag.svg',
                fit: BoxFit.cover,
                semanticsLabel: 'Nigeria flag',
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '+234',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 24,
            color: const Color(0xFF3A3A3A),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('wallet-phone-field'),
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
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
                hintText: '',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UseEmailInsteadRow extends StatelessWidget {
  const _UseEmailInsteadRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.mail_outline_rounded,
              color: AppColors.white,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Use email instead?',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
