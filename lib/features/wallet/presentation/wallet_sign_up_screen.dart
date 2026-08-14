import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

class WalletSignUpScreen extends StatelessWidget {
  const WalletSignUpScreen({super.key});

  static const _artworkAspectRatio = 390 / 472;

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final topGap = compact ? 20.0 : 28.0;
              final artworkTopGap = compact ? 4.0 : 8.0;
              final titleGap = compact ? 8.0 : 12.0;
              final textToButtonGap = compact ? 40.0 : 52.0;
              final bottomGap = compact ? 48.0 : 64.0;
              const headerHeight = 64.0;
              const titleBlockHeight = 72.0;
              const buttonHeight = 52.0;

              final reservedHeight = topGap +
                  headerHeight +
                  artworkTopGap +
                  titleGap +
                  titleBlockHeight +
                  textToButtonGap +
                  buttonHeight +
                  bottomGap;

              final availableArtworkHeight = math.max(
                300.0,
                constraints.maxHeight - reservedHeight,
              );
              final artworkWidth = math.min(
                constraints.maxWidth,
                availableArtworkHeight * _artworkAspectRatio,
              );
              final artworkHeight = artworkWidth / _artworkAspectRatio;
              // Cards sit left of the SVG viewBox center; nudge right to look centered.
              final artworkOpticalOffsetX = artworkWidth * 0.03;

              return Column(
                children: [
                  SizedBox(height: topGap),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _WalletSignUpHeader(onBack: () => _goBack(context)),
                  ),
                  SizedBox(height: artworkTopGap),
                  Center(
                    child: Transform.translate(
                      offset: Offset(artworkOpticalOffsetX, 0),
                      child: SizedBox(
                        width: artworkWidth,
                        height: artworkHeight,
                        child: const CompatibleSvgPicture.asset(
                          'assets/images/wallet sign up card.svg',
                          fit: BoxFit.contain,
                          semanticsLabel: 'CitiRide wallet card',
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: titleGap),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          Text(
                            'CitiRide E-Wallet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'One stop solution to all your payment\nrelated problems',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8F8F8F),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, bottomGap),
                    child: SizedBox(
                      width: double.infinity,
                      height: buttonHeight,
                      child: FilledButton(
                        key: const ValueKey('wallet-sign-up-button'),
                        onPressed: () => context.push('/wallet-get-started'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.citirideYellow,
                          foregroundColor: AppColors.citirideBlack,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WalletSignUpHeader extends StatelessWidget {
  const _WalletSignUpHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              tooltip: 'Back',
            ),
          ),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Wallet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Pay for rides directly from your wallet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
