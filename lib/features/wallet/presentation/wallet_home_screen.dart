import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_wallet_client.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../../shared/widgets/citiride_empty_state.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../profile/domain/rider_profile.dart';
import 'wallet_select_bank_sheet.dart';
import 'wallet_transaction_pin_store.dart';

enum _WalletTxnFilter { all, completed, pending, failed, reversed }

enum _WalletTxnType { payment, topUp, transfer }

class _WalletTransaction {
  const _WalletTransaction({
    required this.id,
    required this.type,
    required this.title,
    required this.timestamp,
    required this.dateLabel,
    required this.timeLabel,
    required this.amount,
    required this.isCredit,
    required this.status,
    required this.rawType,
    required this.reference,
    this.rideId,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.balanceAfter,
    this.fee,
  });

  final String id;
  final _WalletTxnType type;
  final String title;
  final String timestamp;
  final String dateLabel;
  final String timeLabel;
  final String amount;
  final bool isCredit;
  final _WalletTxnFilter status;
  final String rawType;
  final String reference;
  final String? rideId;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final String? balanceAfter;
  final String? fee;

  String get typeLabel {
    return switch (rawType) {
      'top_up' => 'Wallet top up',
      'withdrawal' => 'Bank withdrawal',
      'ride_payment' => 'Ride payment',
      'ride_earning' => 'Ride earning',
      _ => title,
    };
  }

  String get statusLabel {
    return switch (status) {
      _WalletTxnFilter.completed => 'Successful',
      _WalletTxnFilter.pending => 'Pending',
      _WalletTxnFilter.failed => 'Failed',
      _WalletTxnFilter.reversed => 'Reversed',
      _WalletTxnFilter.all => '',
    };
  }
}

class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  final _walletClient = CitirideWalletClient();

  List<_WalletTransaction> _transactions = const [];
  _WalletTxnFilter _filter = _WalletTxnFilter.all;
  bool _balanceVisible = true;
  bool _loading = true;
  double _availableBalance = 0;
  String? _error;

  List<_WalletTransaction> get _filteredTransactions {
    if (_filter == _WalletTxnFilter.all) {
      return _transactions;
    }
    return _transactions
        .where((transaction) => transaction.status == _filter)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWallet(syncFromPaystack: true));
    });
  }

  String _formatMoney(double value) {
    return '₦${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '$hour:$minute $suffix • ${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  _WalletTxnType _mapType(String type) {
    switch (type) {
      case 'top_up':
        return _WalletTxnType.topUp;
      case 'withdrawal':
        return _WalletTxnType.transfer;
      case 'ride_payment':
      case 'ride_earning':
        return _WalletTxnType.payment;
      default:
        return _WalletTxnType.payment;
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String? _metadataString(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  _WalletTxnFilter _mapStatus(String status) {
    switch (status.toLowerCase()) {
      case 'successful':
      case 'success':
      case 'completed':
        return _WalletTxnFilter.completed;
      case 'reversed':
        return _WalletTxnFilter.reversed;
      case 'failed':
      case 'abandoned':
      case 'blocked':
        return _WalletTxnFilter.failed;
      default:
        return _WalletTxnFilter.pending;
    }
  }

  String? _metadataFee(Map<String, dynamic> metadata) {
    final naira = metadata['fee'];
    if (naira is num && naira > 0) {
      return _formatMoney(naira.toDouble());
    }
    final kobo = metadata['feeKobo'];
    if (kobo is num && kobo > 0) {
      return _formatMoney(kobo / 100);
    }
    return null;
  }

  Future<void> _loadWallet({
    bool showSpinner = true,
    bool syncFromPaystack = false,
  }) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final profile = RiderProfileStore.instance.profile.value;
      final email = profile.email.trim().toLowerCase();
      if (email.isNotEmpty) {
        await _walletClient.ensureFundingAccount(
          email: email,
          fullName: profile.fullName,
          phone: profile.phoneNumber,
        );
      }

      if (syncFromPaystack) {
        try {
          await _walletClient.requeryFunding();
        } catch (_) {}
      }

      final wallet = await _walletClient.fetchWallet();
      final txns = await _walletClient.fetchTransactions();

      if (!mounted) return;
      setState(() {
        _availableBalance = wallet.availableBalance;
        _transactions = txns
            .map(
              (txn) => _WalletTransaction(
                id: txn.id,
                type: _mapType(txn.type),
                title: txn.title,
                timestamp: _formatTimestamp(txn.createdAt),
                dateLabel: _formatDate(txn.createdAt),
                timeLabel: _formatTime(txn.createdAt),
                amount: _formatMoney(txn.amount.abs()),
                isCredit: txn.isCredit,
                status: _mapStatus(txn.status),
                rawType: txn.type,
                reference: txn.reference.isNotEmpty ? txn.reference : txn.id,
                rideId: _metadataString(txn.metadata, 'rideId'),
                bankName: _metadataString(txn.metadata, 'bankName'),
                accountNumber: _metadataString(txn.metadata, 'accountNumber'),
                accountName: _metadataString(txn.metadata, 'accountName'),
                balanceAfter: txn.balanceAfter == null
                    ? null
                    : _formatMoney(txn.balanceAfter!),
                fee: _metadataFee(txn.metadata),
              ),
            )
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Unable to load wallet.';
      });
    }
  }

  Future<void> _refreshWallet() {
    return _loadWallet(showSpinner: false, syncFromPaystack: true);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  Future<void> _onWithdraw() async {
    if (!WalletTransactionPinStore.instance.hasPin) {
      final created = await context.push<bool>('/wallet-transaction-pin-setup');
      if (!mounted || created != true) {
        return;
      }
    }

    final bank = await showWalletSelectBankSheet(context);
    if (!mounted || bank == null) {
      return;
    }

    context.push('/wallet-withdraw', extra: bank);
  }

  Future<void> _openTransactionDetails(_WalletTransaction transaction) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetContext) {
        return _WalletTransactionDetailsSheet(transaction: transaction);
      },
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
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.citirideYellow,
                      backgroundColor: const Color(0xFF2A2A2A),
                      onRefresh: _refreshWallet,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 18)),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(
                              child: ValueListenableBuilder<RiderProfile>(
                                valueListenable:
                                    RiderProfileStore.instance.profile,
                                builder: (context, profile, _) {
                                  return _WalletBalanceCard(
                                    name: profile.displayName,
                                    balanceText: _formatMoney(
                                      _availableBalance,
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
                            ),
                          ),
                          if (_error != null)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              sliver: SliverToBoxAdapter(
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFF8A8A),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          if (_loading)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.citirideYellow,
                                  ),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 22)),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(
                              child: _WalletQuickActions(
                                onAddMoney: () =>
                                    context.push('/wallet-add-money'),
                                onWithdraw: _onWithdraw,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                          SliverToBoxAdapter(
                            child: _WalletHistoryHeader(
                              active: _filter,
                              onChanged: (filter) {
                                setState(() => _filter = filter);
                              },
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                            sliver: DecoratedSliver(
                              decoration: const BoxDecoration(
                                color: Color(0xFF1C1C1C),
                              ),
                              sliver: _filteredTransactions.isEmpty
                                  ? SliverToBoxAdapter(
                                      child: _loading
                                          ? const SizedBox(height: 48)
                                          : const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 12,
                                              ),
                                              child: CitirideEmptyState(
                                                compact: true,
                                                icon: Icons
                                                    .receipt_long_outlined,
                                                title: 'No transactions yet',
                                                subtitle:
                                                    'Wallet credits, trip payments, and withdrawals will appear here.',
                                              ),
                                            ),
                                    )
                                  : SliverList.separated(
                                      itemCount: _filteredTransactions.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 16),
                                      itemBuilder: (context, index) {
                                        return _WalletTransactionTile(
                                          transaction:
                                              _filteredTransactions[index],
                                          onTap: () => _openTransactionDetails(
                                            _filteredTransactions[index],
                                          ),
                                        );
                                      },
                                    ),
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
                        : Image.memory(profile.photoBytes!, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${RiderProfile.timeOfDayGreeting()},',
                        style: const TextStyle(
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
                          profile.firstName,
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
                          balanceVisible ? balanceText : '••••••',
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

class _WalletHistoryHeader extends StatelessWidget {
  const _WalletHistoryHeader({
    required this.active,
    required this.onChanged,
  });

  final _WalletTxnFilter active;
  final ValueChanged<_WalletTxnFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
            child: _WalletFilterChips(active: active, onChanged: onChanged),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _WalletFilterChips extends StatelessWidget {
  const _WalletFilterChips({required this.active, required this.onChanged});

  final _WalletTxnFilter active;
  final ValueChanged<_WalletTxnFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = <(_WalletTxnFilter, String)>[
      (_WalletTxnFilter.all, 'All'),
      (_WalletTxnFilter.completed, 'Completed'),
      (_WalletTxnFilter.pending, 'Pending'),
      (_WalletTxnFilter.failed, 'Failed'),
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
  const _WalletTransactionTile({
    required this.transaction,
    required this.onTap,
  });

  final _WalletTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('wallet-txn-tile-${transaction.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
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
                '${transaction.isCredit ? '+' : '-'}${transaction.amount}',
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
          ),
        ),
      ),
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

class _WalletTransactionDetailsSheet extends StatelessWidget {
  const _WalletTransactionDetailsSheet({required this.transaction});

  final _WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final amountColor = transaction.isCredit
        ? const Color(0xFF1FDC5E)
        : const Color(0xFFFF2727);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          key: const ValueKey('wallet-txn-details-sheet'),
          decoration: const BoxDecoration(
            color: Color(0xFF242424),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A5A5A),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Transaction details',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('wallet-txn-details-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: AppColors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TransactionAvatar(type: transaction.type),
                  const SizedBox(height: 12),
                  Text(
                    transaction.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${transaction.isCredit ? '+' : '-'}${transaction.amount}',
                    style: TextStyle(
                      color: amountColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      transaction.statusLabel,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _DetailRow(label: 'Type', value: transaction.typeLabel),
                  if (transaction.dateLabel.isNotEmpty)
                    _DetailRow(label: 'Date', value: transaction.dateLabel),
                  if (transaction.timeLabel.isNotEmpty)
                    _DetailRow(label: 'Time', value: transaction.timeLabel),
                  if (transaction.rideId != null)
                    _DetailRow(label: 'Ride ID', value: transaction.rideId!),
                  if (transaction.accountName != null)
                    _DetailRow(
                      label: 'Account name',
                      value: transaction.accountName!,
                    ),
                  if (transaction.bankName != null)
                    _DetailRow(label: 'Bank', value: transaction.bankName!),
                  if (transaction.accountNumber != null)
                    _DetailRow(
                      label: 'Account number',
                      value: transaction.accountNumber!,
                    ),
                  if (transaction.fee != null)
                    _DetailRow(label: 'Transfer fee', value: transaction.fee!),
                  if (transaction.balanceAfter != null)
                    _DetailRow(
                      label: 'Balance after',
                      value: transaction.balanceAfter!,
                    ),
                  _DetailRow(label: 'Reference', value: transaction.reference),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
