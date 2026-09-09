import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_wallet_client.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_flow_widgets.dart';

class WalletAddMoneyScreen extends StatefulWidget {
  const WalletAddMoneyScreen({super.key});

  @override
  State<WalletAddMoneyScreen> createState() => _WalletAddMoneyScreenState();
}

class _WalletAddMoneyScreenState extends State<WalletAddMoneyScreen> {
  final _walletClient = CitirideWalletClient();

  bool _balanceVisible = true;
  bool _loading = true;
  bool _checkingPayment = false;
  bool _simulatingTest = false;
  String? _error;
  CitirideWallet? _wallet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadFundingAccount());
    });
  }

  Future<void> _loadFundingAccount() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = RiderProfileStore.instance.profile.value;
      final email = profile.email.trim().toLowerCase();
      if (email.isEmpty) {
        throw const CitirideWalletException(
          'Add your email in Personal Info before funding your wallet.',
        );
      }

      final wallet = await _walletClient.ensureFundingAccount(
        email: email,
        fullName: profile.fullName,
        phone: profile.phoneNumber,
      );

      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Unable to load funding account.';
      });
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/wallet');
  }

  Future<void> _copyValue(String label, String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _onPaymentCompleted() async {
    if (_checkingPayment) return;
    setState(() => _checkingPayment = true);

    try {
      final before = _wallet?.availableBalance ?? 0;
      final wallet = await _walletClient.requeryFunding();
      if (!mounted) return;

      setState(() {
        _wallet = wallet;
        _checkingPayment = false;
      });

      final credited = wallet.availableBalance > before;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            credited
                ? 'Payment found. Balance updated to ${_formatBalance(wallet.availableBalance)}.'
                : 'Paystack is rechecking this account. In test mode, use Paystack Demo Bank (not your real bank app), or tap Simulate test deposit.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      if (credited) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/wallet');
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _checkingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is CitirideWalletException
                ? error.message
                : 'Could not check for payment yet.',
          ),
        ),
      );
    }
  }

  Future<void> _simulateTestDeposit() async {
    if (_simulatingTest) return;
    setState(() => _simulatingTest = true);
    try {
      final wallet = await _walletClient.simulateTestDeposit(amount: 1000);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _simulatingTest = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Test deposit credited. Balance ${_formatBalance(wallet.availableBalance)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _simulatingTest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is CitirideWalletException
                ? error.message
                : 'Test deposit failed.',
          ),
        ),
      );
    }
  }

  String _formatBalance(double value) {
    return '₦${value.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        )}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final funding = _wallet?.fundingAccount;

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
                    child: RefreshIndicator(
                      color: AppColors.citirideYellow,
                      onRefresh: _loadFundingAccount,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          bottomInset + 140,
                        ),
                        child: Column(
                          children: [
                            ValueListenableBuilder<RiderProfile>(
                              valueListenable:
                                  RiderProfileStore.instance.profile,
                              builder: (context, profile, _) {
                                return _AddMoneyBalanceCard(
                                  name: profile.displayName,
                                  balanceText: _wallet == null
                                      ? '₦—.——'
                                      : _formatBalance(
                                          _wallet!.availableBalance,
                                        ),
                                  balanceVisible: _balanceVisible,
                                  onToggleVisibility: () {
                                    setState(
                                      () =>
                                          _balanceVisible = !_balanceVisible,
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: CircularProgressIndicator(
                                  color: AppColors.citirideYellow,
                                ),
                              )
                            else if (_error != null)
                              _ErrorCard(
                                message: _error!,
                                onRetry: _loadFundingAccount,
                              )
                            else
                              _AddMoneyDetailsCard(
                                riderName: RiderProfileStore
                                    .instance.profile.value.displayName,
                                accountName: funding?.accountName ?? '',
                                accountNumber: funding?.accountNumber ?? '',
                                bankName: funding?.bankName ?? '',
                                onCopy: _copyValue,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _wallet?.testMode == true
                                  ? 'Test mode: do not transfer from your real bank app. Use Paystack’s Demo Bank to pay this virtual account, or tap Simulate test deposit below. Live mode credits after Paystack confirms the transfer.'
                                  : 'Transfer to this account from your bank app. Your wallet updates automatically after Paystack confirms the payment.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF8F8F8F),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 24),
                            WalletPrimaryButton(
                              key: const ValueKey(
                                'wallet-payment-completed-button',
                              ),
                              label: _checkingPayment
                                  ? 'Checking payment…'
                                  : 'I’ve sent the transfer',
                              enabled: funding?.accountNumber.isNotEmpty ==
                                      true &&
                                  !_checkingPayment &&
                                  !_simulatingTest,
                              onPressed: _onPaymentCompleted,
                            ),
                            if (_wallet?.testMode == true) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _simulatingTest
                                    ? null
                                    : _simulateTestDeposit,
                                child: Text(
                                  _simulatingTest
                                      ? 'Crediting…'
                                      : 'Simulate test deposit (₦1,000)',
                                  style: const TextStyle(
                                    color: AppColors.citirideYellow,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Try again',
              style: TextStyle(color: AppColors.citirideYellow),
            ),
          ),
        ],
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
    required this.balanceText,
    required this.balanceVisible,
    required this.onToggleVisibility,
  });

  final String name;
  final String balanceText;
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
                        balanceVisible ? balanceText : '••••••',
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
  const _AddMoneyDetailsCard({
    required this.riderName,
    required this.accountName,
    required this.accountNumber,
    required this.bankName,
    required this.onCopy,
  });

  final String riderName;
  final String accountName;
  final String accountNumber;
  final String bankName;
  final Future<void> Function(String label, String value) onCopy;

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
          Text(
            riderName,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _CopyDetailRow(
            label: "Recipient's account name",
            value: accountName.isEmpty ? '—' : accountName,
            onCopy: () => onCopy("Recipient's account name", accountName),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          _CopyDetailRow(
            label: 'Account number',
            value: accountNumber.isEmpty ? '—' : accountNumber,
            onCopy: () => onCopy('Account number', accountNumber),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          _CopyDetailRow(
            label: 'Bank',
            value: bankName.isEmpty ? '—' : bankName,
            onCopy: () => onCopy('Bank', bankName),
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
