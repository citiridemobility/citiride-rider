import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';

class WalletGetStartedScreen extends StatefulWidget {
  const WalletGetStartedScreen({super.key});

  @override
  State<WalletGetStartedScreen> createState() => _WalletGetStartedScreenState();
}

class _WalletGetStartedScreenState extends State<WalletGetStartedScreen> {
  bool _isAgeConfirmed = false;
  bool _isIdentityConfirmed = false;

  bool get _canContinue => _isAgeConfirmed && _isIdentityConfirmed;

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet-sign-up');
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
                _WalletFlowTopBar(
                  onBack: _goBack,
                  onNeedHelp: () {},
                ),
                const SizedBox(height: 28),
                const Text(
                  'Before you get started',
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
                  'Confirm you meet these requirements',
                  style: TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 32),
                _RequirementRow(
                  key: const ValueKey('wallet-age-requirement'),
                  icon: Icons.person_outline_rounded,
                  title: 'You are 18 years and older',
                  description:
                      'You must be at least 18 years old to open an account.',
                  checked: _isAgeConfirmed,
                  onChanged: (value) {
                    setState(() => _isAgeConfirmed = value);
                  },
                ),
                const SizedBox(height: 22),
                _RequirementRow(
                  key: const ValueKey('wallet-identity-requirement'),
                  icon: Icons.badge_outlined,
                  title: 'You have a valid BVN or NIN',
                  description:
                      'Use a valid BVN or NIN to help us verify your identity quickly.',
                  checked: _isIdentityConfirmed,
                  onChanged: (value) {
                    setState(() => _isIdentityConfirmed = value);
                  },
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('wallet-get-started-button'),
                    onPressed: _canContinue
                        ? () => context.push('/wallet-email')
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.citirideYellow,
                      foregroundColor: AppColors.citirideBlack,
                      disabledBackgroundColor: const Color(0xFF918900),
                      disabledForegroundColor: const Color(0xFF514D00),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
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

class _WalletFlowTopBar extends StatelessWidget {
  const _WalletFlowTopBar({
    required this.onBack,
    required this.onNeedHelp,
  });

  final VoidCallback onBack;
  final VoidCallback onNeedHelp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          tooltip: 'Back',
        ),
        const Spacer(),
        TextButton(
          onPressed: onNeedHelp,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.citirideYellow,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Need Help?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.checked,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!checked),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _WalletCheckbox(
              checked: checked,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletCheckbox extends StatelessWidget {
  const _WalletCheckbox({
    required this.checked,
    required this.onChanged,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!checked),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
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
    );
  }
}
