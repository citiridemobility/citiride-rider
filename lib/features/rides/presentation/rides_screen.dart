import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/cancel_ride_request_sheet.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../domain/ride_history.dart';

enum _RidesTab { upcoming, past }

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key, this.initialTab = 'upcoming'});

  final String initialTab;

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  late _RidesTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'past' ? _RidesTab.past : _RidesTab.upcoming;
  }

  Future<void> _cancelRide(RideHistoryItem ride) async {
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => const CancelRideRequestSheet(),
    );

    if (shouldCancel != true || !mounted) {
      return;
    }

    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: {'pickup': ride.pickup, 'destination': ride.destination},
    );
    context.go(selectRideUri.toString());
  }

  void _openRideDetails(RideHistoryItem ride) {
    context.push(
      Uri(
        path: '/ride-details',
        queryParameters: {'rideId': ride.id},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rides = _tab == _RidesTab.upcoming
        ? upcomingRideHistoryItems
        : pastRideHistoryItems;

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
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.citirideBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 35, 16, 112),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rides',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _RideTabPill(
                            label: 'Upcoming Rides',
                            active: _tab == _RidesTab.upcoming,
                            onTap: () => setState(() {
                              _tab = _RidesTab.upcoming;
                            }),
                          ),
                          const SizedBox(width: 7),
                          _RideTabPill(
                            label: 'Past',
                            active: _tab == _RidesTab.past,
                            onTap: () => setState(() {
                              _tab = _RidesTab.past;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: rides.length,
                          separatorBuilder: (context, index) {
                            return const SizedBox(height: 12);
                          },
                          itemBuilder: (context, index) {
                            final ride = rides[index];
                            return _RideHistoryCard(
                              ride: ride,
                              showCancel: _tab == _RidesTab.upcoming,
                              showStatus: _tab == _RidesTab.past,
                              onTap: () => _openRideDetails(ride),
                              onCancel: () => _cancelRide(ride),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 39,
                child: const Center(
                  child: CitirideBottomNav(activeTab: CitirideNavTab.rides),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RideTabPill extends StatelessWidget {
  const _RideTabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: active
                ? null
                : Border.all(color: const Color(0xFFB7B7B7), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.citirideBlack : const Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({
    required this.ride,
    required this.showCancel,
    required this.showStatus,
    required this.onTap,
    required this.onCancel,
  });

  final RideHistoryItem ride;
  final bool showCancel;
  final bool showStatus;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  Color get _amountColor {
    return ride.status == RideHistoryStatus.completed
        ? const Color(0xFF168BFF)
        : AppColors.citirideYellow;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('ride-card-${ride.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 70,
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const CompatibleSvgPicture.asset(
                'assets/images/Profile.svg',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                semanticsLabel: 'Ride rider avatar',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ride.dateLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8C8C8C),
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              height: 1.1,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (showStatus) ...[
                          const SizedBox(width: 6),
                          _RideStatusPill(status: ride.status),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ride.pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.1,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ride.amount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _amountColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCancel) ...[
                const SizedBox(width: 12),
                _CancelRideIconButton(onTap: onCancel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RideStatusPill extends StatelessWidget {
  const _RideStatusPill({required this.status});

  final RideHistoryStatus status;

  @override
  Widget build(BuildContext context) {
    final completed = status == RideHistoryStatus.completed;

    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFC6FFC2) : const Color(0xFFFFB7DD),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        completed ? 'Completed' : 'Cancelled',
        style: TextStyle(
          color: completed ? const Color(0xFF00A413) : const Color(0xFFFF007A),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CancelRideIconButton extends StatelessWidget {
  const _CancelRideIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancel ride',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close,
            color: AppColors.citirideBlack,
            size: 25,
          ),
        ),
      ),
    );
  }
}
