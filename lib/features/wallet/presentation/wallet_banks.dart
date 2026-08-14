import 'package:flutter/material.dart';

import '../../../shared/widgets/compatible_svg_picture.dart';

enum WalletBankId { moniepoint, firstBank, uba }

class WalletBank {
  const WalletBank({
    required this.id,
    required this.name,
    required this.logoAsset,
  });

  final WalletBankId id;
  final String name;
  final String logoAsset;
}

const walletBanks = <WalletBank>[
  WalletBank(
    id: WalletBankId.moniepoint,
    name: 'Moniepoint',
    logoAsset: 'assets/images/moniepoint.svg',
  ),
  WalletBank(
    id: WalletBankId.firstBank,
    name: 'First Bank',
    logoAsset: 'assets/images/firstbank.svg',
  ),
  WalletBank(
    id: WalletBankId.uba,
    name: 'UBA',
    logoAsset: 'assets/images/uba.svg',
  ),
];

class WalletBankLogo extends StatelessWidget {
  const WalletBankLogo({
    super.key,
    required this.bank,
    this.size = 36,
  });

  final WalletBank bank;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: CompatibleSvgPicture.asset(
          bank.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticsLabel: '${bank.name} logo',
        ),
      ),
    );
  }
}
