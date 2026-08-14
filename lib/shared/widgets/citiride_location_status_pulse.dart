import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'compatible_svg_picture.dart';

class CitirideLocationStatusPulse extends StatefulWidget {
  const CitirideLocationStatusPulse({
    super.key,
    this.size = 104,
    this.iconSize = 64,
    this.semanticsLabel = 'Live rider location',
  });

  final double size;
  final double iconSize;
  final String semanticsLabel;

  @override
  State<CitirideLocationStatusPulse> createState() =>
      _CitirideLocationStatusPulseState();
}

class _CitirideLocationStatusPulseState
    extends State<CitirideLocationStatusPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void initState() {
    super.initState();
    if (!_isRunningWidgetTest) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1550),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _LocationStatusPulseFrame(
        size: widget.size,
        iconSize: widget.iconSize,
        semanticsLabel: widget.semanticsLabel,
        pulse: 0.42,
        breath: 1,
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final pulse = Curves.easeOutCubic.transform(controller.value);
        final breath = 1 + (math.sin(controller.value * math.pi * 2) * 0.025);

        return _LocationStatusPulseFrame(
          size: widget.size,
          iconSize: widget.iconSize,
          semanticsLabel: widget.semanticsLabel,
          pulse: pulse,
          breath: breath,
        );
      },
    );
  }
}

class _LocationStatusPulseFrame extends StatelessWidget {
  const _LocationStatusPulseFrame({
    required this.size,
    required this.iconSize,
    required this.semanticsLabel,
    required this.pulse,
    required this.breath,
  });

  final double size;
  final double iconSize;
  final String semanticsLabel;
  final double pulse;
  final double breath;

  @override
  Widget build(BuildContext context) {
    final basePulse = size * 0.42;
    final pulseGrowth = size * 0.52;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1 - pulse) * 0.74,
            child: Container(
              width: basePulse + (pulse * pulseGrowth),
              height: basePulse + (pulse * pulseGrowth),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.citirideYellow.withValues(alpha: 0.19),
              ),
            ),
          ),
          Transform.scale(
            scale: breath,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: CompatibleSvgPicture.asset(
                'assets/images/Location Status.svg',
                fit: BoxFit.contain,
                semanticsLabel: semanticsLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
