import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import 'wallet_flow_widgets.dart';

class WalletWithdrawalSuccessScreen extends StatelessWidget {
  const WalletWithdrawalSuccessScreen({super.key});

  void _backToHome(BuildContext context) {
    context.go('/wallet');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

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
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 16),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1FDC5E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.white,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Withdrawal Successful',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const Spacer(flex: 3),
                WalletPrimaryButton(
                  key: const ValueKey('wallet-withdrawal-back-home-button'),
                  label: 'Back To Home',
                  enabled: true,
                  onPressed: () => _backToHome(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
