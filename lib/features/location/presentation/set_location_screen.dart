import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/location/location_permission_service.dart';

class SetLocationScreen extends StatefulWidget {
  const SetLocationScreen({super.key});

  @override
  State<SetLocationScreen> createState() => _SetLocationScreenState();
}

class _SetLocationScreenState extends State<SetLocationScreen> {
  bool _isRequestingLocation = false;

  Future<void> _requestLocationPermission() async {
    if (_isRequestingLocation) {
      return;
    }

    setState(() {
      _isRequestingLocation = true;
    });

    bool granted;
    try {
      granted = await const LocationPermissionService()
          .requestWhenInUse()
          .timeout(const Duration(seconds: 18), onTimeout: () => false);
    } on Object {
      granted = false;
    }

    if (!mounted) {
      return;
    }

    if (granted) {
      context.go('/home');
      return;
    }

    setState(() {
      _isRequestingLocation = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location permission is required.')),
    );
  }

  void _goHome() {
    if (_isRequestingLocation) {
      return;
    }

    context.go('/home');
  }

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
        body: Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: const _SetLocationBackdrop(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.26),
                ),
              ),
            ),
            Positioned.fill(
              child: _SetLocationPrompt(
                isRequestingLocation: _isRequestingLocation,
                onSetLocation: _requestLocationPermission,
                onDoLater: _goHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetLocationBackdrop extends StatelessWidget {
  const _SetLocationBackdrop();

  @override
  Widget build(BuildContext context) {
    return const _MapArtworkLayer();
  }
}

class _MapArtworkLayer extends StatelessWidget {
  const _MapArtworkLayer();

  static const _sourceSize = Size(688, 1398);
  static const _phoneFrame = Rect.fromLTWH(148, 28, 390, 844);

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('set-location-map-background'),
      child: ColoredBox(
        color: const Color(0xFF050505),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.max(
              constraints.maxWidth / _phoneFrame.width,
              constraints.maxHeight / _phoneFrame.height,
            );
            final imageWidth = _sourceSize.width * scale;
            final imageHeight = _sourceSize.height * scale;
            final left =
                -_phoneFrame.left * scale +
                ((constraints.maxWidth - (_phoneFrame.width * scale)) / 2);
            final top =
                -_phoneFrame.top * scale +
                ((constraints.maxHeight - (_phoneFrame.height * scale)) / 2);

            return ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    width: imageWidth,
                    height: imageHeight,
                    child: Image.asset(
                      'assets/images/home_default_map.png',
                      fit: BoxFit.fill,
                      semanticLabel: 'Set location map background',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SetLocationPrompt extends StatelessWidget {
  const _SetLocationPrompt({
    required this.isRequestingLocation,
    required this.onSetLocation,
    required this.onDoLater,
  });

  final bool isRequestingLocation;
  final VoidCallback onSetLocation;
  final VoidCallback onDoLater;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 56),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.citirideBlack,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 28,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 4,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton.filled(
                      onPressed: isRequestingLocation ? null : onDoLater,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE4E4EA),
                        disabledBackgroundColor: const Color(
                          0xFFE4E4EA,
                        ).withValues(alpha: 0.52),
                        foregroundColor: AppColors.citirideBlack,
                        disabledForegroundColor: AppColors.citirideBlack
                            .withValues(alpha: 0.46),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close location prompt',
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 1),
                    const Text(
                      'Set your location?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 34),
                      child: Text(
                        'Set your location so we can find rides near\nyou and pick you up at the right spot',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: isRequestingLocation ? null : onSetLocation,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.citirideYellow,
                          disabledBackgroundColor: AppColors.citirideYellow
                              .withValues(alpha: 0.62),
                          foregroundColor: AppColors.citirideBlack,
                          disabledForegroundColor: AppColors.citirideBlack
                              .withValues(alpha: 0.68),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Text(
                          isRequestingLocation
                              ? 'Checking location'
                              : 'Set location',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: isRequestingLocation ? null : onDoLater,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          disabledForegroundColor: AppColors.white.withValues(
                            alpha: 0.44,
                          ),
                          side: const BorderSide(color: AppColors.white),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Do it later',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
