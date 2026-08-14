import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = [
    _OnboardingPageData(
      artworkAsset: 'assets/images/onboarding screen1 image.svg',
      artworkLabel: 'Onboarding slide 1 artwork',
      titlePrefix: 'Book a ride in',
      titleIconAsset: 'assets/images/clockimage.svg',
      titleIconLabel: 'Clock icon',
      titleSuffix: 'seconds',
      titleSuffixItalic: true,
      subtitle: 'Safe drivers, Clear prices, No stress',
      iconSize: 42,
    ),
    _OnboardingPageData(
      artworkAsset: 'assets/images/onboarding screen2 image.svg',
      artworkLabel: 'Onboarding slide 2 artwork',
      titlePrefix: 'Pay',
      titleIconAsset: 'assets/images/coin.svg',
      titleIconLabel: 'Coin icon',
      titleSuffix: 'your way',
      titleSuffixItalic: true,
      subtitle:
          'Avoid bank network delays when you\npay with your in-app wallet',
      iconSize: 39,
    ),
    _OnboardingPageData(
      artworkAsset: 'assets/images/onboarding screen3 image.svg',
      artworkLabel: 'Onboarding slide 3 artwork',
      titlePrefix: 'Ride more, save',
      titleIconAsset: 'assets/images/discount.svg',
      titleIconLabel: 'Discount icon',
      titleSuffix: 'more!',
      titleSuffixItalic: true,
      subtitle: 'Unlock special ride promos and wallet\nrewards.',
      iconSize: 42,
    ),
  ];

  final PageController _pageController = PageController();
  int _currentPage = 0;

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (_isLastPage) {
      _goToWelcome();
      return;
    }

    if (!_pageController.hasClients) {
      return;
    }

    _pageController.animateToPage(
      _currentPage + 1,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToWelcome() async {
    await const CitirideSessionStore().markOnboardingSeen();
    if (!mounted) {
      return;
    }
    context.go('/welcome');
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                const SizedBox(height: 31),
                SizedBox(
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _PageIndicator(
                        currentPage: _currentPage,
                        pageCount: _pages.length,
                      ),
                      if (!_isLastPage)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _goToWelcome,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.white,
                              minimumSize: const Size(44, 28),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Skip',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    itemBuilder: (context, index) {
                      return _OnboardingPage(
                        data: _pages[index],
                        buttonLabel: index == _pages.length - 1
                            ? 'Continue'
                            : 'Next',
                        onContinue: _goToNextPage,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.buttonLabel,
    required this.onContinue,
  });

  final _OnboardingPageData data;
  final String buttonLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const artworkAspectRatio = 354 / 403;
        const preferredArtworkWidth = 354.0;
        final compact = constraints.maxHeight < 640;
        final availableArtworkWidth = math.min(
          constraints.maxWidth,
          preferredArtworkWidth,
        );
        final preferredArtworkHeight =
            availableArtworkWidth / artworkAspectRatio;
        final maxArtworkHeight =
            constraints.maxHeight * (compact ? 0.48 : 0.59);
        final artworkHeight = math.min(
          preferredArtworkHeight,
          maxArtworkHeight,
        );
        final artworkWidth = artworkHeight * artworkAspectRatio;

        return Column(
          children: [
            SizedBox(
              width: artworkWidth,
              height: artworkHeight,
              child: CompatibleSvgPicture.asset(
                data.artworkAsset,
                fit: BoxFit.contain,
                semanticsLabel: data.artworkLabel,
              ),
            ),
            SizedBox(height: compact ? 20 : 42),
            _OnboardingTitle(data: data),
            SizedBox(height: compact ? 12 : 17),
            Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB9B9B9),
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.32,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 204,
              height: 48,
              child: FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.citirideYellow,
                  foregroundColor: AppColors.citirideBlack,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 28 : 64),
          ],
        );
      },
    );
  }
}

class _OnboardingTitle extends StatelessWidget {
  const _OnboardingTitle({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      color: AppColors.white,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.15,
      letterSpacing: 0,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      runSpacing: 2,
      children: [
        Text(data.titlePrefix, textAlign: TextAlign.center, style: titleStyle),
        SizedBox.square(
          dimension: data.iconSize,
          child: CompatibleSvgPicture.asset(
            data.titleIconAsset,
            fit: BoxFit.contain,
            semanticsLabel: data.titleIconLabel,
          ),
        ),
        Text(
          data.titleSuffix,
          textAlign: TextAlign.center,
          style: titleStyle.copyWith(
            fontStyle: data.titleSuffixItalic ? FontStyle.italic : null,
          ),
        ),
      ],
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(pageCount, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 14,
          height: 14,
          margin: EdgeInsets.only(right: index == pageCount - 1 ? 0 : 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFFD9D9D9) : const Color(0xFF050505),
          ),
        );
      }),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.artworkAsset,
    required this.artworkLabel,
    required this.titlePrefix,
    required this.titleIconAsset,
    required this.titleIconLabel,
    required this.titleSuffix,
    required this.subtitle,
    required this.iconSize,
    this.titleSuffixItalic = false,
  });

  final String artworkAsset;
  final String artworkLabel;
  final String titlePrefix;
  final String titleIconAsset;
  final String titleIconLabel;
  final String titleSuffix;
  final String subtitle;
  final double iconSize;
  final bool titleSuffixItalic;
}
