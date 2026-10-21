import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../profile/domain/rider_profile.dart';
import '../../wallet/presentation/wallet_enrollment_store.dart';
import '../../wallet/presentation/wallet_transaction_pin_store.dart';

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
      WalletEnrollmentStore.instance.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
      WalletTransactionPinStore.instance.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
    ]);

    if (!mounted) {
      return;
    }

    try {
      const sessionStore = CitirideSessionStore();
      final hasCompletedAuth = await sessionStore.hasCompletedAuth().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!mounted) {
        return;
      }

      if (hasCompletedAuth) {
        final email = await sessionStore.signedInEmail();
        if (email != null) {
          await RiderProfileStore.instance
              .restoreForAccount(
                email: email,
                uid: CitirideAuthService().currentUid,
              )
              .timeout(const Duration(seconds: 5), onTimeout: () {});
        }
        if (!mounted) {
          return;
        }
        context.go('/home');
        return;
      }

      final hasSeenOnboarding = await sessionStore.hasSeenOnboarding().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
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
          child: Center(
            child: CompatibleSvgPicture.asset(
              'assets/images/citiridelogo.svg',
              width: 168,
              height: 168,
              fit: BoxFit.contain,
              semanticsLabel: 'CitiRide',
              placeholderBuilder: (_) =>
                  const SizedBox(width: 168, height: 168),
              errorBuilder: (context, error, stackTrace) => const Text(
                'CitiRide',
                style: TextStyle(
                  color: AppColors.citirideYellow,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
