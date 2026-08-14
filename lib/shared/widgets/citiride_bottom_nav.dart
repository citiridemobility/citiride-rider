import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../features/wallet/presentation/wallet_flow_widgets.dart';
import 'compatible_svg_picture.dart';

enum CitirideNavTab { home, rides, wallet }

class CitirideBottomNav extends StatelessWidget {
  const CitirideBottomNav({
    super.key,
    required this.activeTab,
    this.onHome,
    this.onRides,
    this.onWallet,
  });

  final CitirideNavTab activeTab;
  final VoidCallback? onHome;
  final VoidCallback? onRides;
  final VoidCallback? onWallet;

  void _openWallet(BuildContext context) {
    // Already on a wallet screen — don't force another unlock.
    if (activeTab == CitirideNavTab.wallet) {
      return;
    }

    if (WalletEnrollmentStore.instance.isEnrolled) {
      context.go('/wallet-unlock-passcode');
      return;
    }

    context.go('/wallet-sign-up');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.citirideYellow,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NavItem(
            key: const ValueKey('citiride-nav-home'),
            assetName: 'assets/images/home_icon.svg',
            label: 'Home',
            active: activeTab == CitirideNavTab.home,
            onTap: onHome ?? () => context.go('/home'),
          ),
          const SizedBox(width: 4),
          _NavItem(
            key: const ValueKey('citiride-nav-rides'),
            assetName: 'assets/images/rides_icon.svg',
            label: 'Rides',
            active: activeTab == CitirideNavTab.rides,
            onTap: onRides ?? () => context.go('/rides'),
          ),
          const SizedBox(width: 4),
          _NavItem(
            key: const ValueKey('citiride-nav-wallet'),
            assetName: 'assets/images/wallet_icon.svg',
            label: 'Wallet',
            active: activeTab == CitirideNavTab.wallet,
            onTap: onWallet ?? () => _openWallet(context),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.assetName,
    required this.label,
    required this.active,
    required this.onTap,
  });

  static const _inactiveColor = Color(0xFF7E7800);

  final String assetName;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? AppColors.white : _inactiveColor;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 38,
            width: active ? 90 : 50,
            padding: EdgeInsets.symmetric(horizontal: active ? 10 : 9),
            decoration: BoxDecoration(
              color: active ? AppColors.citirideBlack : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
                  child: CompatibleSvgPicture.asset(
                    assetName,
                    width: active ? 20 : 23,
                    height: active ? 20 : 23,
                    fit: BoxFit.contain,
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
