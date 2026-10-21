import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/citiride_auth_service.dart';
import '../../core/session/citiride_session_store.dart';
import '../../features/profile/domain/rider_profile.dart';

Future<void> showCitirideLogoutDialog(BuildContext context) {
  var loggingOut = false;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss logout',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: Center(
            child: _LogoutDialogCard(
              onCancel: () {
                if (loggingOut) return;
                Navigator.of(dialogContext).pop();
              },
              onConfirm: () async {
                if (loggingOut) return;
                loggingOut = true;
                final router = GoRouter.of(context);
                Navigator.of(dialogContext, rootNavigator: true).pop();
                try {
                  await CitirideAuthService().signOut();
                  // Wallet enrollment and the transaction PIN are encrypted
                  // device credentials. They must survive logout so this
                  // rider is asked to unlock, rather than enroll, next time.
                  await Future.wait<void>([
                    const CitirideSessionStore().clearAuth(),
                    RiderProfileStore.instance.clear(),
                  ]);
                } finally {
                  router.go('/welcome');
                }
              },
            ),
          ),
        ),
      );
    },
  );
}

class _LogoutDialogCard extends StatelessWidget {
  const _LogoutDialogCard({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width < 360 ? width - 40 : 320.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1F1F1F),
              Color(0xFF141414),
            ],
          ),
          border: Border.all(
            color: AppColors.citirideYellow.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFF6B6B),
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Log out?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You’ll need to sign in again with your email to continue riding.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.45,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => onConfirm(),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFFFF3B3B),
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Log out',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Stay signed in',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
