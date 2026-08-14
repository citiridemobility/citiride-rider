import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../domain/ride_history.dart';

class RideDetailsScreen extends StatelessWidget {
  const RideDetailsScreen({super.key, required this.ride});

  final RideHistoryItem ride;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.citirideBlack,
      ),
      child: Scaffold(
        backgroundColor: AppColors.citirideBlack,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              12,
              28,
              12,
              MediaQuery.paddingOf(context).bottom + 36,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  key: const ValueKey('ride-details-back-button'),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go('/rides?tab=past');
                  },
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: AppColors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const CompatibleSvgPicture.asset(
                      'assets/images/Profile.svg',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      semanticsLabel: 'Ride details avatar',
                    ),
                    const SizedBox(width: 9),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.detailTitle,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ride.detailDate,
                          style: const TextStyle(
                            color: Color(0xFFA0A0A0),
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                const _RideDetailsMap(),
                const SizedBox(height: 25),
                _RouteTimeline(ride: ride),
                const SizedBox(height: 25),
                _PaymentSummaryCard(ride: ride),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideDetailsMap extends StatelessWidget {
  const _RideDetailsMap();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 163,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.white, width: 1.3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: const [
              CompatibleSvgPicture.asset(
                'assets/images/Basemap image.svg',
                fit: BoxFit.cover,
                semanticsLabel: 'Ride details route map',
              ),
              CustomPaint(painter: _RideDetailsMapPainter()),
            ],
          ),
        ),
      ),
    );
  }
}

class _RideDetailsMapPainter extends CustomPainter {
  const _RideDetailsMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final routePaint = Paint()
      ..color = AppColors.citirideYellow
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.33,
        size.height * 0.55,
        size.width * 0.37,
        size.height * 0.43,
      )
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.24,
        size.width * 0.57,
        size.height * 0.18,
      );
    canvas.drawPath(path, routePaint);

    _drawPoint(canvas, Offset(size.width * 0.20, size.height * 0.66));
    _drawPin(canvas, Offset(size.width * 0.57, size.height * 0.18));
  }

  void _drawPoint(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 8, Paint()..color = AppColors.citirideYellow);
    canvas.drawCircle(center, 5, Paint()..color = AppColors.white);
    canvas.drawCircle(center, 3.5, Paint()..color = AppColors.citirideYellow);
  }

  void _drawPin(Canvas canvas, Offset topCenter) {
    final pinPaint = Paint()..color = AppColors.citirideYellow;
    final path = Path()
      ..moveTo(topCenter.dx, topCenter.dy + 21)
      ..cubicTo(
        topCenter.dx - 13,
        topCenter.dy + 9,
        topCenter.dx - 11,
        topCenter.dy - 8,
        topCenter.dx,
        topCenter.dy - 8,
      )
      ..cubicTo(
        topCenter.dx + 11,
        topCenter.dy - 8,
        topCenter.dx + 13,
        topCenter.dy + 9,
        topCenter.dx,
        topCenter.dy + 21,
      )
      ..close();
    canvas.drawPath(path, pinPaint);
    canvas.drawCircle(
      topCenter.translate(0, 3),
      4,
      Paint()..color = AppColors.citirideBlack,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({required this.ride});

  final RideHistoryItem ride;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 0),
      child: Column(
        children: [
          _RouteStopRow(label: ride.pickup, icon: const _TimelineStartIcon()),
          const SizedBox(height: 16),
          _RouteStopRow(
            label: ride.destination,
            icon: const _TimelineEndIcon(),
          ),
        ],
      ),
    );
  }
}

class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({required this.label, required this.icon});

  final String label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 16, child: Center(child: icon)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineStartIcon extends StatelessWidget {
  const _TimelineStartIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: const BoxDecoration(
        color: AppColors.citirideYellow,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _TimelineEndIcon extends StatelessWidget {
  const _TimelineEndIcon();

  @override
  Widget build(BuildContext context) {
    return const CompatibleSvgPicture.asset(
      'assets/images/location icon.svg',
      width: 18,
      height: 18,
      fit: BoxFit.contain,
      semanticsLabel: 'Destination',
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({required this.ride});

  final RideHistoryItem ride;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  ride.paymentMethod,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                ride.amount,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFF8F8F8F)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    color: AppColors.citirideYellow,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                ride.amount,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
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
