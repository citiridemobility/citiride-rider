import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../profile/domain/rider_profile.dart';
import '../../wallet/presentation/wallet_enrollment_store.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minimumSplashDuration = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    unawaited(_completeStartup());
  }

  Future<void> _completeStartup() async {
    unawaited(FirebaseBootstrap.initialize());

    // Wait for local persistence before routing so wallet/onboarding state
    // is ready when the first real screen opens.
    await Future.wait<void>([
      Future<void>.delayed(_minimumSplashDuration),
      RiderProfileStore.instance.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
      WalletEnrollmentStore.instance.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
    ]);

    if (!mounted) {
      return;
    }

    try {
      const sessionStore = CitirideSessionStore();
      final hasCompletedAuth = await sessionStore
          .hasCompletedAuth()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!mounted) {
        return;
      }

      if (hasCompletedAuth) {
        context.go('/home');
        return;
      }

      final hasSeenOnboarding = await sessionStore
          .hasSeenOnboarding()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!mounted) {
        return;
      }

      context.go(hasSeenOnboarding ? '/welcome' : '/onboarding');
    } on Object {
      if (!mounted) {
        return;
      }
      context.go('/onboarding');
    }
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
          // The PNG logo is dark on transparent — nearly invisible on black —
          // so always show the yellow wordmark with the mark above it.
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/citiride_app logo.png',
                  width: 168,
                  height: 168,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'CitiRide',
                  style: TextStyle(
                    color: AppColors.citirideYellow,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    height: 1,
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
