import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Primary confirm control for the rider app (tap only — no swipe).
class CitirideSlideButton extends StatelessWidget {
  const CitirideSlideButton({
    super.key,
    required this.label,
    required this.onConfirm,
    this.enabled = true,
    this.height = 52,
    this.backgroundColor = AppColors.citirideYellow,
    this.foregroundColor = AppColors.citirideBlack,
    this.disabledBackgroundColor = const Color(0xFF3A3A3A),
    this.disabledForegroundColor = const Color(0xFF8F8F8F),
  });

  final String label;
  final VoidCallback onConfirm;
  final bool enabled;
  final double height;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color disabledForegroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        onPressed: enabled ? onConfirm : null,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
