import 'package:flutter/material.dart';

import '../../../shared/widgets/compatible_svg_picture.dart';

const _nigeriaBankLogoCdn = 'https://nigerianbanks.xyz/logo';

String? localLogoAssetForCode(String code) {
  switch (code) {
    case '011':
      return 'assets/images/firstbank.svg';
    case '033':
      return 'assets/images/uba.svg';
    case '50515':
      return 'assets/images/moniepoint.svg';
    default:
      return null;
  }
}

String? nigeriaBankLogoUrl(String? slug, {String? explicit}) {
  final fromApi = explicit?.trim() ?? '';
  if (fromApi.isNotEmpty) return fromApi;
  final clean = slug?.trim().toLowerCase() ?? '';
  if (clean.isEmpty) return null;
  return '$_nigeriaBankLogoCdn/$clean.png';
}

class WalletBank {
  const WalletBank({
    required this.name,
    required this.paystackCode,
    this.logoAsset,
    this.logoUrl,
    this.slug,
  });

  final String name;
  /// Paystack NUBAN bank code used for resolve + transfer recipient.
  final String paystackCode;
  final String? logoAsset;
  final String? logoUrl;
  final String? slug;

  factory WalletBank.fromPaystackJson(Map<String, dynamic> json) {
    final code = (json['code'] as String?)?.trim() ?? '';
    final slug = (json['slug'] as String?)?.trim();
    return WalletBank(
      name: (json['name'] as String?)?.trim() ?? 'Bank',
      paystackCode: code,
      slug: slug,
      logoUrl: nigeriaBankLogoUrl(
        slug,
        explicit: json['logo'] as String?,
      ),
      logoAsset: localLogoAssetForCode(code),
    );
  }
}

/// Fallback list only if Paystack banks API is unavailable.
const walletBanksFallback = <WalletBank>[
  WalletBank(
    name: 'Access Bank',
    paystackCode: '044',
    slug: 'access-bank',
    logoUrl: '$_nigeriaBankLogoCdn/access-bank.png',
  ),
  WalletBank(
    name: 'First Bank of Nigeria',
    paystackCode: '011',
    slug: 'first-bank-of-nigeria',
    logoAsset: 'assets/images/firstbank.svg',
    logoUrl: '$_nigeriaBankLogoCdn/first-bank-of-nigeria.png',
  ),
  WalletBank(
    name: 'Guaranty Trust Bank',
    paystackCode: '058',
    slug: 'guaranty-trust-bank',
    logoUrl: '$_nigeriaBankLogoCdn/guaranty-trust-bank.png',
  ),
  WalletBank(
    name: 'Moniepoint MFB',
    paystackCode: '50515',
    slug: 'moniepoint-mfb-ng',
    logoAsset: 'assets/images/moniepoint.svg',
    logoUrl: '$_nigeriaBankLogoCdn/moniepoint-mfb-ng.png',
  ),
  WalletBank(
    name: 'United Bank For Africa',
    paystackCode: '033',
    slug: 'united-bank-for-africa',
    logoAsset: 'assets/images/uba.svg',
    logoUrl: '$_nigeriaBankLogoCdn/united-bank-for-africa.png',
  ),
  WalletBank(
    name: 'Zenith Bank',
    paystackCode: '057',
    slug: 'zenith-bank',
    logoUrl: '$_nigeriaBankLogoCdn/zenith-bank.png',
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

    final networkLogo = bank.logoUrl;
    if (networkLogo != null && networkLogo.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: Colors.white,
          child: Image.network(
            networkLogo,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _BankInitials(
                name: bank.name,
                size: size,
                radius: radius,
              );
            },
            errorBuilder: (_, _, _) => _BankInitials(
              name: bank.name,
              size: size,
              radius: radius,
            ),
          ),
        ),
      );
    }

    return _BankInitials(name: bank.name, size: size, radius: radius);
  }
}

class _BankInitials extends StatelessWidget {
  const _BankInitials({
    required this.name,
    required this.size,
    required this.radius,
  });

  final String name;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
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
