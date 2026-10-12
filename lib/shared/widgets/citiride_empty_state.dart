import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class CitirideEmptyState extends StatefulWidget {
  const CitirideEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;
  final String? detail;

  @override
  State<CitirideEmptyState> createState() => _CitirideEmptyStateState();
}

class _CitirideEmptyStateState extends State<CitirideEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.96, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _opacity = Tween<double>(
      begin: 0.68,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 56.0 : 74.0;
    final glyphSize = widget.compact ? 26.0 : 34.0;
    final detail = widget.detail?.trim();

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 18 : 28,
          vertical: widget.compact ? 12 : 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: AppColors.citirideYellow.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.citirideYellow.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: AppColors.citirideYellow,
                    size: glyphSize,
                  ),
                ),
              ),
            ),
            SizedBox(height: widget.compact ? 14 : 18),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white,
                fontSize: widget.compact ? 16 : 18,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF8F8F8F),
                fontSize: widget.compact ? 12 : 13,
                fontWeight: FontWeight.w400,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                detail,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.citirideYellow.withValues(alpha: 0.85),
                  fontSize: widget.compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
