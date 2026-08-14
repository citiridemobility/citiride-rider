import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
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
            initialChildSize: 0.42,
            minChildSize: 0.28,
            maxChildSize: 0.88,
            expand: false,
            snap: true,
            snapSizes: const [0.42, 0.72, 0.88],
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

class _SelectBankSheet extends StatelessWidget {
  const _SelectBankSheet({
    required this.scrollController,
    required this.onSelected,
  });

  final ScrollController scrollController;
  final ValueChanged<WalletBank> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: const Color(0xFF1C1C1C),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scrollController,
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
          const SizedBox(height: 18),
          for (var i = 0; i < walletBanks.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _BankOptionTile(
              bank: walletBanks[i],
              onTap: () => onSelected(walletBanks[i]),
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
            Text(
              bank.name,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
