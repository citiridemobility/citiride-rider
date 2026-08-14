import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'compatible_svg_picture.dart';

class CancelRideRequestSheet extends StatelessWidget {
  const CancelRideRequestSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('cancel-ride-request-sheet'),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.paddingOf(context).bottom + 18,
        ),
        decoration: const BoxDecoration(
          color: AppColors.citirideBlack,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 49,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4EA),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),
            const CompatibleSvgPicture.asset(
              'assets/images/modal cancel ride icon.svg',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              semanticsLabel: 'Cancel ride warning',
            ),
            const SizedBox(height: 18),
            const Text(
              'Cancel ride request?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Canceling now will stop this ride request.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9C9C9C),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: FilledButton(
                key: const ValueKey('confirm-cancel-ride-button'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3838),
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                child: const Text('Cancel Ride'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: FilledButton(
                key: const ValueKey('keep-ride-button'),
                onPressed: () => Navigator.of(context).pop(false),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.citirideYellow,
                  foregroundColor: AppColors.citirideBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                child: const Text('Keep Ride'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
