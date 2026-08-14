import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // Belt-and-suspenders: any path to welcome means onboarding is done.
    unawaited(const CitirideSessionStore().markOnboardingSeen());
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
              final compact = constraints.maxHeight < 700;
              final topGap = compact ? 20.0 : 26.0;
              final artworkGap = compact ? 42.0 : 86.0;
              final buttonGap = compact ? 62.0 : 116.0;
              const bottomGap = 8.0;
              final reservedHeight =
                  topGap +
                  68 +
                  artworkGap +
                  buttonGap +
                  48 +
                  15 +
                  48 +
                  bottomGap;
              final artworkSize = math.min(
                354.0,
                math.min(
                  constraints.maxWidth - 36,
                  math.max(260.0, constraints.maxHeight - reservedHeight),
                ),
              );

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: topGap),
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  letterSpacing: 0,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Sign up or Log in to continue',
                                style: TextStyle(
                                  color: Color(0xFF8F8F8F),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  height: 1.35,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: artworkGap),
                        Center(
                          child: SizedBox.square(
                            dimension: artworkSize,
                            child: const CompatibleSvgPicture.asset(
                              'assets/images/welcome screen image.svg',
                              fit: BoxFit.contain,
                              semanticsLabel: 'Welcome artwork',
                            ),
                          ),
                        ),
                        SizedBox(height: buttonGap),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 13),
                          child: _WelcomeActions(),
                        ),
                        SizedBox(height: bottomGap),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  const _WelcomeActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () => context.go('/enter-number'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.citirideYellow,
              foregroundColor: AppColors.citirideBlack,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
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
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => context.go('/enter-number'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.citirideYellow,
              side: const BorderSide(color: AppColors.citirideYellow),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              'Log in',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
