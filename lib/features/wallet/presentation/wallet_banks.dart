import 'package:flutter/material.dart';

import '../../../shared/widgets/compatible_svg_picture.dart';

class WalletBank {
  const WalletBank({
    required this.name,
    required this.paystackCode,
    this.logoAsset,
    this.slug,
  });

  final String name;
  /// Paystack NUBAN bank code used for resolve + transfer recipient.
  final String paystackCode;
  final String? logoAsset;
  final String? slug;

  factory WalletBank.fromPaystackJson(Map<String, dynamic> json) {
    return WalletBank(
      name: (json['name'] as String?)?.trim() ?? 'Bank',
      paystackCode: (json['code'] as String?)?.trim() ?? '',
      slug: (json['slug'] as String?)?.trim(),
    );
  }
}

/// Fallback list only if Paystack banks API is unavailable.
const walletBanksFallback = <WalletBank>[
  WalletBank(
    name: 'Access Bank',
    paystackCode: '044',
    logoAsset: null,
  ),
  WalletBank(
    name: 'First Bank of Nigeria',
    paystackCode: '011',
    logoAsset: 'assets/images/firstbank.svg',
  ),
  WalletBank(
    name: 'Guaranty Trust Bank',
    paystackCode: '058',
  ),
  WalletBank(
    name: 'Moniepoint MFB',
    paystackCode: '50515',
    logoAsset: 'assets/images/moniepoint.svg',
  ),
  WalletBank(
    name: 'United Bank For Africa',
    paystackCode: '033',
    logoAsset: 'assets/images/uba.svg',
  ),
  WalletBank(
    name: 'Zenith Bank',
    paystackCode: '057',
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
    final asset = bank.logoAsset;

    if (asset != null && asset.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: CompatibleSvgPicture.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            semanticsLabel: '${bank.name} logo',
          ),
        ),
      );
    }

    final trimmed = bank.name.trim();
    final initial = trimmed.isEmpty ? 'B' : trimmed[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: radius,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
