import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_flow_widgets.dart';

class WalletAddMoneyScreen extends StatefulWidget {
  const WalletAddMoneyScreen({super.key});

  @override
  State<WalletAddMoneyScreen> createState() => _WalletAddMoneyScreenState();
}

class _WalletAddMoneyScreenState extends State<WalletAddMoneyScreen> {
  bool _balanceVisible = true;

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/wallet');
  }

  Future<void> _copyValue(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  void _onPaymentCompleted() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment marked as completed')),
    );

    if (context.canPop()) {
      context.pop();
      return;
    }

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
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _AddMoneyHeader(onBack: _goBack),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        bottomInset + 140,
                      ),
                      child: Column(
                        children: [
                          ValueListenableBuilder<RiderProfile>(
                            valueListenable: RiderProfileStore.instance.profile,
                            builder: (context, profile, _) {
                              return _AddMoneyBalanceCard(
                                name: profile.displayName,
                                balanceVisible: _balanceVisible,
                                onToggleVisibility: () {
                                  setState(
                                    () => _balanceVisible = !_balanceVisible,
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          _AddMoneyDetailsCard(
                            onCopy: _copyValue,
                          ),
                          const SizedBox(height: 24),
                          WalletPrimaryButton(
                            key: const ValueKey(
                              'wallet-payment-completed-button',
                            ),
                            label: 'Payment completed',
                            enabled: true,
                            onPressed: _onPaymentCompleted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset + 24,
              child: const Center(
                child: CitirideBottomNav(activeTab: CitirideNavTab.wallet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMoneyHeader extends StatelessWidget {
  const _AddMoneyHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
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
          const Text(
            'Add money',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMoneyBalanceCard extends StatelessWidget {
  const _AddMoneyBalanceCard({
    required this.name,
    required this.balanceVisible,
    required this.onToggleVisibility,
  });

  final String name;
  final bool balanceVisible;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: AppColors.citirideYellow,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.citirideBlack,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Balance',
                  style: TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        balanceVisible ? '₦435.54' : '••••••',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleVisibility,
                      icon: Icon(
                        balanceVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF8F8F8F),
                      ),
                      tooltip: balanceVisible ? 'Hide balance' : 'Show balance',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMoneyDetailsCard extends StatelessWidget {
  const _AddMoneyDetailsCard({required this.onCopy});

  final Future<void> Function(String label, String value) onCopy;

  static const _recipientName = 'CitiRide - Umoru Osigbemhe';
  static const _accountNumber = '98291029281';
  static const _bank = 'Paystack-titan';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF3A3A3A),
            child: Icon(Icons.person, color: AppColors.white, size: 30),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ahmed Singer',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _CopyDetailRow(
            label: "Recipient's account name",
            value: _recipientName,
            onCopy: () => onCopy("Recipient's account name", _recipientName),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          _CopyDetailRow(
            label: 'Account number',
            value: _accountNumber,
            onCopy: () => onCopy('Account number', _accountNumber),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          _CopyDetailRow(
            label: 'Bank',
            value: _bank,
            onCopy: () => onCopy('Bank', _bank),
          ),
        ],
      ),
    );
  }
}

class _CopyDetailRow extends StatelessWidget {
  const _CopyDetailRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(
              Icons.copy_rounded,
              color: AppColors.citirideYellow,
              size: 20,
            ),
            tooltip: 'Copy $label',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
        ],
      ),
    );
  }
}
