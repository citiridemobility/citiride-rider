import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';

class CancelRideReasonScreen extends StatefulWidget {
  const CancelRideReasonScreen({
    super.key,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
  });

  final String rideType;
  final String paymentMethod;

  @override
  State<CancelRideReasonScreen> createState() => _CancelRideReasonScreenState();
}

class _CancelRideReasonScreenState extends State<CancelRideReasonScreen> {
  static const _reasons = [
    'Car not moving towards me',
    'Long pickup time',
    'Accidental request',
    'Driver asked to pay off the app',
    'Driver asked to cancel',
    'Driver not at pickup point',
    'Driver asked for personal info',
    'Other',
  ];

  String? _selectedReason;

  bool get _canCancel => _selectedReason != null;

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/arriving');
  }

  void _cancelRide() {
    if (!_canCancel) {
      return;
    }

    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
      },
    );
    context.go(selectRideUri.toString());
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth > 430
                  ? 430.0
                  : constraints.maxWidth;

              return Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            23,
                            52,
                            23,
                            MediaQuery.paddingOf(context).bottom + 124,
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 56),
                              for (final reason in _reasons)
                                _CancelReasonOption(
                                  reason: reason,
                                  isSelected: _selectedReason == reason,
                                  onTap: () {
                                    setState(() {
                                      _selectedReason = reason;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 16,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            key: const ValueKey('cancel-reason-back-button'),
                            onPressed: _goBack,
                            padding: EdgeInsets.zero,
                            splashRadius: 24,
                            icon: const Icon(
                              Icons.arrow_back,
                              color: AppColors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 64,
                        right: 64,
                        top: 25,
                        child: Text(
                          'What went wrong?',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 50,
                        right: 50,
                        bottom: MediaQuery.paddingOf(context).bottom + 66,
                        child: FilledButton(
                          key: const ValueKey('cancel-reason-submit-button'),
                          onPressed: _canCancel ? _cancelRide : null,
                          style: ButtonStyle(
                            minimumSize: WidgetStateProperty.all(
                              const Size.fromHeight(50),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return const Color(0xFF682222);
                              }
                              return const Color(0xFFFF3838);
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return AppColors.white.withValues(alpha: 0.45);
                              }
                              return AppColors.white;
                            }),
                            textStyle: WidgetStateProperty.all(
                              const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          child: const Text('Cancel ride'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CancelReasonOption extends StatelessWidget {
  const _CancelReasonOption({
    required this.reason,
    required this.isSelected,
    required this.onTap,
  });

  final String reason;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: reason,
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('cancel-reason-$reason'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 53,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.white.withValues(alpha: 0.68),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  reason,
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
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.citirideYellow
                        : const Color(0xFF3F4148),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: isSelected ? 8 : 0,
                    height: isSelected ? 8 : 0,
                    decoration: const BoxDecoration(
                      color: AppColors.citirideYellow,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
