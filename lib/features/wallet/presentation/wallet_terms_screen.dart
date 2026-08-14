import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import 'wallet_flow_widgets.dart';

class WalletTermsScreen extends StatefulWidget {
  const WalletTermsScreen({super.key});

  @override
  State<WalletTermsScreen> createState() => _WalletTermsScreenState();
}

class _WalletTermsScreenState extends State<WalletTermsScreen> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;
  late final TapGestureRecognizer _processingRecognizer;

  bool _acceptedTerms = false;
  bool _acceptedProcessing = false;
  bool _acceptedMarketing = false;
  bool _isSubmitting = false;

  bool get _canContinue =>
      _acceptedTerms && _acceptedProcessing && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _showLinkSnack('Terms and Conditions');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _showLinkSnack('Data privacy statement');
    _processingRecognizer = TapGestureRecognizer()
      ..onTap = () => _showLinkSnack('Data processing consent');
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _processingRecognizer.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet-phone-number');
  }

  Future<void> _continue() async {
    if (!_canContinue) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await showWalletTimedLoadingDialog(
      context,
      message: 'Please wait',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    context.push('/wallet-setup-passcode');
  }

  void _showLinkSnack(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label will be available soon.')),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                WalletFlowTopBar(onBack: _goBack),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 2,
                  color: AppColors.citirideYellow,
                ),
                const SizedBox(height: 28),
                const Text(
                  'CitiRide needs your consent to continue',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 28),
                _ConsentRow(
                  checked: _acceptedTerms,
                  onChanged: (value) {
                    setState(() => _acceptedTerms = value);
                  },
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: 'I have read and agreed to the '),
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: const TextStyle(
                            color: Color(0xFF168BFF),
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: _termsRecognizer,
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Data privacy statement',
                          style: const TextStyle(
                            color: Color(0xFF168BFF),
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: _privacyRecognizer,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _ConsentRow(
                  checked: _acceptedProcessing,
                  onChanged: (value) {
                    setState(() => _acceptedProcessing = value);
                  },
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: 'I have read and agreed to the '),
                        TextSpan(
                          text: 'Data processing consent',
                          style: const TextStyle(
                            color: Color(0xFF168BFF),
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: _processingRecognizer,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _ConsentRow(
                  checked: _acceptedMarketing,
                  onChanged: (value) {
                    setState(() => _acceptedMarketing = value);
                  },
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text:
                              'I would like to receive marketing and promotional information ',
                        ),
                        TextSpan(
                          text: '(optional)',
                          style: TextStyle(color: Color(0xFF8F8F8F)),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                WalletPrimaryButton(
                  key: const ValueKey('wallet-terms-continue-button'),
                  label: 'Continue',
                  enabled: _canContinue,
                  onPressed: () => unawaited(_continue()),
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

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.checked,
    required this.onChanged,
    required this.child,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!checked),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: checked ? AppColors.citirideYellow : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: checked ? AppColors.citirideYellow : AppColors.white,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.citirideBlack,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
