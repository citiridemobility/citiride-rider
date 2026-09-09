import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_wallet_client.dart';
import 'wallet_banks.dart';

Future<WalletBank?> showWalletSelectBankSheet(BuildContext context) {
  return showModalBottomSheet<WalletBank>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (sheetContext) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheetContext).pop(),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            expand: false,
            snap: true,
            snapSizes: const [0.72, 0.92],
            builder: (context, scrollController) {
              return _SelectBankSheet(
                scrollController: scrollController,
                onSelected: (bank) => Navigator.of(sheetContext).pop(bank),
              );
            },
          ),
        ],
      );
    },
  );
}

class _SelectBankSheet extends StatefulWidget {
  const _SelectBankSheet({
    required this.scrollController,
    required this.onSelected,
  });

  final ScrollController scrollController;
  final ValueChanged<WalletBank> onSelected;

  @override
  State<_SelectBankSheet> createState() => _SelectBankSheetState();
}

class _SelectBankSheetState extends State<_SelectBankSheet> {
  final _walletClient = CitirideWalletClient();
  final _searchController = TextEditingController();

  List<WalletBank> _banks = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadBanks();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final banks = await _walletClient.fetchBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks.isEmpty ? walletBanksFallback : banks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _banks = walletBanksFallback;
        _loading = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Using offline bank list.';
      });
    }
  }

  List<WalletBank> get _filtered {
    if (_query.isEmpty) return _banks;
    return _banks
        .where((bank) => bank.name.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final banks = _filtered;

    return Material(
      color: const Color(0xFF1C1C1C),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 24),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF8F8F8F),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Icon(
                Icons.account_balance_outlined,
                color: AppColors.white,
                size: 22,
              ),
              SizedBox(width: 10),
              Text(
                'Select Bank',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.white),
            cursorColor: AppColors.citirideYellow,
            decoration: InputDecoration(
              hintText: 'Search banks',
              hintStyle: const TextStyle(color: Color(0xFF8F8F8F)),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF8F8F8F)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.citirideYellow,
                ),
              ),
            )
          else if (banks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No banks match your search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8F8F8F)),
              ),
            )
          else
            for (var i = 0; i < banks.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _BankOptionTile(
                bank: banks[i],
                onTap: () => widget.onSelected(banks[i]),
              ),
            ],
        ],
      ),
    );
  }
}

class _BankOptionTile extends StatelessWidget {
  const _BankOptionTile({
    required this.bank,
    required this.onTap,
  });

  final WalletBank bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            WalletBankLogo(bank: bank, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                bank.name,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
