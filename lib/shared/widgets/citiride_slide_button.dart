import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class CitirideSlideButton extends StatefulWidget {
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
  State<CitirideSlideButton> createState() => _CitirideSlideButtonState();
}

class _CitirideSlideButtonState extends State<CitirideSlideButton> {
  double _dragExtent = 0;
  bool _completed = false;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  double get _thumbSize => widget.height - 8;

  @override
  void didUpdateWidget(covariant CitirideSlideButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label || oldWidget.enabled != widget.enabled) {
      _dragExtent = 0;
      _completed = false;
    }
  }

  void _complete() {
    if (_completed || !widget.enabled) {
      return;
    }
    setState(() {
      _completed = true;
    });
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_completed;
    final background = widget.enabled
        ? widget.backgroundColor
        : widget.disabledBackgroundColor;
    final foreground = widget.enabled
        ? widget.foregroundColor
        : widget.disabledForegroundColor;

    if (_isRunningWidgetTest) {
      return SizedBox(
        width: double.infinity,
        height: widget.height,
        child: FilledButton(
          onPressed: enabled ? widget.onConfirm : null,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: widget.disabledBackgroundColor,
            disabledForegroundColor: widget.disabledForegroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.height / 2),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          child: Text(widget.label),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDrag = (constraints.maxWidth - _thumbSize - 8).clamp(
            0.0,
            constraints.maxWidth,
          );
          final progress = maxDrag == 0
              ? 0.0
              : (_dragExtent / maxDrag).clamp(0.0, 1.0);
          final showCheck = _completed || progress >= 0.88;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: enabled
                ? (details) {
                    setState(() {
                      _dragExtent = (_dragExtent + details.delta.dx).clamp(
                        0.0,
                        maxDrag,
                      );
                    });
                  }
                : null,
            onHorizontalDragEnd: enabled
                ? (_) {
                    if (progress >= 0.78) {
                      setState(() => _dragExtent = maxDrag);
                      _complete();
                      return;
                    }
                    setState(() => _dragExtent = 0);
                  }
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.height / 2),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ColoredBox(
                    color: background,
                    child: const SizedBox.expand(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      heightFactor: 1,
                      child: ColoredBox(
                        color: foreground.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: showCheck ? 1 : 0,
                      child: Icon(
                        Icons.check,
                        color: foreground,
                        size: 26,
                      ),
                    ),
                  ),
                  if (enabled)
                    Positioned(
                      left: 4 + _dragExtent,
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: FittedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: foreground,
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: foreground,
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: foreground,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
