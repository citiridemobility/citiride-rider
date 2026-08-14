import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_select_bank_sheet.dart';

enum _WalletTxnFilter { all, completed, pending, reversed }

enum _WalletTxnType { payment, topUp, transfer }

class _WalletTransaction {
  const _WalletTransaction({
    required this.type,
    required this.title,
    required this.timestamp,
    required this.amount,
    required this.isCredit,
    required this.status,
  });

  final _WalletTxnType type;
  final String title;
  final String timestamp;
  final String amount;
  final bool isCredit;
  final _WalletTxnFilter status;
}

class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  static const _transactions = <_WalletTransaction>[
    _WalletTransaction(
      type: _WalletTxnType.payment,
      title: 'Payment to Ahmed',
      timestamp: '2:30 PM • Fri, 21 Jun 2025',
      amount: '₦435.54',
      isCredit: false,
      status: _WalletTxnFilter.completed,
    ),
    _WalletTransaction(
      type: _WalletTxnType.topUp,
      title: 'Wallet Top Up',
      timestamp: '2:30 PM • Fri, 21 Jun 2025',
      amount: '₦435.54',
      isCredit: true,
      status: _WalletTxnFilter.completed,
    ),
    _WalletTransaction(
      type: _WalletTxnType.transfer,
      title: 'Transfer to Osi',
      timestamp: '2:30 PM • Fri, 21 Jun 2025',
      amount: '₦435.54',
      isCredit: false,
      status: _WalletTxnFilter.pending,
    ),
  ];

  _WalletTxnFilter _filter = _WalletTxnFilter.all;
  bool _balanceVisible = true;

  List<_WalletTransaction> get _filteredTransactions {
    if (_filter == _WalletTxnFilter.all) {
      return _transactions;
    }
    return _transactions
        .where((transaction) => transaction.status == _filter)
        .toList();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  Future<void> _onWithdraw() async {
    final bank = await showWalletSelectBankSheet(context);
    if (!mounted || bank == null) {
      return;
    }

    context.push('/wallet-withdraw', extra: bank);
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
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _WalletHomeHeader(onBack: _goBack),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ValueListenableBuilder<RiderProfile>(
                      valueListenable: RiderProfileStore.instance.profile,
                      builder: (context, profile, _) {
                        return _WalletBalanceCard(
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
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _WalletQuickActions(
                      onAddMoney: () => context.push('/wallet-add-money'),
                      onWithdraw: _onWithdraw,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 22),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Transaction History',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _WalletFilterChips(
                              active: _filter,
                              onChanged: (filter) {
                                setState(() => _filter = filter);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                              itemCount: _filteredTransactions.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                return _WalletTransactionTile(
                                  transaction: _filteredTransactions[index],
                                );
                              },
                            ),
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
              bottom: MediaQuery.paddingOf(context).bottom + 24,
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

class _WalletHomeHeader extends StatelessWidget {
  const _WalletHomeHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
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
          ValueListenableBuilder<RiderProfile>(
            valueListenable: RiderProfileStore.instance.profile,
            builder: (context, profile, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB9D1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.citirideYellow.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: profile.photoBytes == null
                        ? const Padding(
                            padding: EdgeInsets.all(6),
                            child: CompatibleSvgPicture.asset(
                              'assets/images/Profile.svg',
                              fit: BoxFit.contain,
                              semanticsLabel: 'Profile picture',
                            ),
                          )
                        : Image.memory(
                            profile.photoBytes!,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome,',
                        style: TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({
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
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF5E700), Color(0xFF8F8700)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.citirideBlack,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          ColoredBox(
            color: const Color(0xFF161616),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Balance',
                    style: TextStyle(
                      color: Color(0xFF8B8B8B),
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
                          balanceVisible ? '₦150.00' : '••••••',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 28,
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
                          color: const Color(0xFF8B8B8B),
                        ),
                        tooltip: balanceVisible
                            ? 'Hide balance'
                            : 'Show balance',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletQuickActions extends StatelessWidget {
  const _WalletQuickActions({
    required this.onAddMoney,
    required this.onWithdraw,
  });

  final VoidCallback onAddMoney;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _WalletActionButton(
          icon: Icons.add,
          label: 'Add money',
          onTap: onAddMoney,
        ),
        const SizedBox(width: 36),
        _WalletActionButton(
          icon: Icons.account_balance_outlined,
          label: 'Withdraw',
          onTap: onWithdraw,
        ),
      ],
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.citirideBlack, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletFilterChips extends StatelessWidget {
  const _WalletFilterChips({
    required this.active,
    required this.onChanged,
  });

  final _WalletTxnFilter active;
  final ValueChanged<_WalletTxnFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = <(_WalletTxnFilter, String)>[
      (_WalletTxnFilter.all, 'All'),
      (_WalletTxnFilter.completed, 'Completed'),
      (_WalletTxnFilter.pending, 'Pending'),
      (_WalletTxnFilter.reversed, 'Reversed'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in filters) ...[
            _FilterChip(
              label: entry.$2,
              selected: active == entry.$1,
              onTap: () => onChanged(entry.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.white : const Color(0xFF4A4A4A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.citirideBlack : AppColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile({required this.transaction});

  final _WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TransactionAvatar(type: transaction.type),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                transaction.timestamp,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        Text(
          transaction.amount,
          style: TextStyle(
            color: transaction.isCredit
                ? const Color(0xFF1FDC5E)
                : const Color(0xFFFF2727),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _TransactionAvatar extends StatelessWidget {
  const _TransactionAvatar({required this.type});

  final _WalletTxnType type;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case _WalletTxnType.payment:
        return const CircleAvatar(
          radius: 22,
          backgroundColor: Color(0xFF3A3A3A),
          child: Icon(Icons.person, color: AppColors.white),
        );
      case _WalletTxnType.topUp:
        return Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFF1B3B28),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.south_west,
            color: Color(0xFF1FDC5E),
            size: 20,
          ),
        );
      case _WalletTxnType.transfer:
        return Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFF3B1B1B),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.north_east,
            color: Color(0xFFFF2727),
            size: 20,
          ),
        );
    }
  }
}
