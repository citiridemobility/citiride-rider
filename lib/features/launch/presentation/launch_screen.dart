import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/firebase/firebase_bootstrap.dart';

class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key, required this.firebaseStatus});

  final FirebaseStatus firebaseStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  const _BrandMark(),
                  const SizedBox(width: 12),
                  Text(
                    'citiride',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: () {},
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(child: _MapPreview()),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _RideRequestPanel(firebaseStatus: firebaseStatus),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.local_taxi_rounded, color: AppColors.white),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surface),
      child: CustomPaint(
        painter: _MapPreviewPainter(
          roadColor: colorScheme.outlineVariant,
          parkColor: AppColors.primary.withValues(alpha: 0.10),
          routeColor: AppColors.primary,
        ),
        child: Center(
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RideRequestPanel extends StatelessWidget {
  const _RideRequestPanel({required this.firebaseStatus});

  final FirebaseStatus firebaseStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where are you going?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            readOnly: true,
            decoration: InputDecoration(
              hintText: 'Enter destination',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: () {},
                tooltip: 'Choose on map',
                icon: const Icon(Icons.map_outlined),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _QuickDestination(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickDestination(
                  icon: Icons.work_rounded,
                  label: 'Work',
                  onPressed: () {},
                ),
              ),
            ],
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 14),
            _FirebaseStatusNote(firebaseStatus: firebaseStatus),
          ],
        ],
      ),
    );
  }
}

class _QuickDestination extends StatelessWidget {
  const _QuickDestination({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _FirebaseStatusNote extends StatelessWidget {
  const _FirebaseStatusNote({required this.firebaseStatus});

  final FirebaseStatus firebaseStatus;

  @override
  Widget build(BuildContext context) {
    final color = firebaseStatus.isReady ? AppColors.primary : AppColors.danger;

    return Row(
      children: [
        Icon(
          firebaseStatus.isReady
              ? Icons.cloud_done_rounded
              : Icons.cloud_off_rounded,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            firebaseStatus.isReady
                ? 'Firebase connected'
                : 'Firebase waiting for project config',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter({
    required this.roadColor,
    required this.parkColor,
    required this.routeColor,
  });

  final Color roadColor;
  final Color parkColor;
  final Color routeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = roadColor
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final routePaint = Paint()
      ..color = routeColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final parkPaint = Paint()..color = parkColor;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.10, 120, 88),
        const Radius.circular(8),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.58, size.height * 0.18, 132, 96),
        const Radius.circular(8),
      ),
      parkPaint,
    );

    canvas.drawLine(
      Offset(-20, size.height * 0.25),
      Offset(size.width + 20, size.height * 0.45),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, -20),
      Offset(size.width * 0.72, size.height + 20),
      roadPaint,
    );
    canvas.drawLine(
      Offset(-20, size.height * 0.78),
      Offset(size.width + 20, size.height * 0.62),
      roadPaint,
    );

    final route = Path()
      ..moveTo(size.width * 0.18, size.height * 0.70)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.58,
        size.width * 0.48,
        size.height * 0.64,
        size.width * 0.56,
        size.height * 0.48,
      )
      ..cubicTo(
        size.width * 0.66,
        size.height * 0.30,
        size.width * 0.76,
        size.height * 0.34,
        size.width * 0.86,
        size.height * 0.24,
      );
    canvas.drawPath(route, routePaint);
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) {
    return roadColor != oldDelegate.roadColor ||
        parkColor != oldDelegate.parkColor ||
        routeColor != oldDelegate.routeColor;
  }
}
