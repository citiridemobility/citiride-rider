import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/location/citiride_fare.dart';
import '../../../core/location/citiride_route.dart';
import '../../../core/location/citiride_route_service.dart';
import '../../../core/location/route_query.dart';
import '../../../shared/widgets/citiride_live_route_map.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

enum _RideOption { regular, vip }

enum _PaymentMethod { cash, wallet }

class SelectRideScreen extends StatefulWidget {
  const SelectRideScreen({
    super.key,
    this.initialRide = 'regular',
    this.initialPayment = 'cash',
    this.initialPickup = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
  });

  final String initialRide;
  final String initialPayment;
  final String initialPickup;
  final String initialDestination;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;

  @override
  State<SelectRideScreen> createState() => _SelectRideScreenState();
}

class _SelectRideScreenState extends State<SelectRideScreen> {
  final _routeService = CitirideRouteService();
  _RideOption _selectedRide = _RideOption.regular;
  _PaymentMethod _selectedPayment = _PaymentMethod.cash;
  CitirideRoute? _route;
  bool _isLoadingRoute = false;
  int _routeLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _applyInitialSelections();
    _loadRoute();
  }

  @override
  void didUpdateWidget(covariant SelectRideScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRide != oldWidget.initialRide ||
        widget.initialPayment != oldWidget.initialPayment) {
      _applyInitialSelections();
    }

    if (!_sameLatLng(
          widget.initialPickupLatLng,
          oldWidget.initialPickupLatLng,
        ) ||
        !_sameLatLng(
          widget.initialDestinationLatLng,
          oldWidget.initialDestinationLatLng,
        )) {
      _loadRoute();
    }
  }

  void _applyInitialSelections() {
    _selectedRide = widget.initialRide == 'vip'
        ? _RideOption.vip
        : _RideOption.regular;
    _selectedPayment = widget.initialPayment == 'wallet'
        ? _PaymentMethod.wallet
        : _PaymentMethod.cash;
  }

  Future<void> _loadRoute() async {
    final pickup = widget.initialPickupLatLng;
    final destination = widget.initialDestinationLatLng;
    final generation = ++_routeLoadGeneration;

    if (pickup == null || destination == null) {
      setState(() {
        _route = null;
        _isLoadingRoute = false;
      });
      return;
    }

    setState(() {
      _isLoadingRoute = true;
    });

    final route = await _routeService.routeBetween(
      origin: pickup,
      destination: destination,
    );

    if (!mounted || generation != _routeLoadGeneration) {
      return;
    }

    setState(() {
      _route = route;
      _isLoadingRoute = false;
    });
  }

  bool _sameLatLng(LatLng? first, LatLng? second) {
    if (first == null || second == null) {
      return first == second;
    }

    return first.latitude == second.latitude &&
        first.longitude == second.longitude;
  }

  Map<String, String> _routeQueryParameters() {
    return {
      'ride': _selectedRide.name,
      'payment': _selectedPayment.name,
      'pickup': widget.initialPickup,
      'destination': widget.initialDestination,
      ...latLngToQuery('pickup', widget.initialPickupLatLng),
      ...latLngToQuery('destination', widget.initialDestinationLatLng),
    };
  }

  void _selectRide(_RideOption ride) {
    setState(() {
      _selectedRide = ride;
    });
  }

  void _openPaymentOptions() {
    final paymentUri = Uri(
      path: '/payment-options',
      queryParameters: _routeQueryParameters(),
    );
    context.push(paymentUri.toString());
  }

  void _continueToPickup() {
    final pickupUri = Uri(
      path: '/select-pickup',
      queryParameters: _routeQueryParameters(),
    );
    context.push(pickupUri.toString());
  }

  void _editRoute({bool showStop = false}) {
    final routeUri = Uri(
      path: '/route',
      queryParameters: {
        ..._routeQueryParameters(),
        if (showStop) 'showStop': 'true',
      },
    );
    context.push(routeUri.toString());
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
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
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.citirideBlack,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = math.min(
              402.0,
              math.max(360.0, constraints.maxHeight * 0.48),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _SelectRideMap(
                    route: _route,
                    isLoadingRoute: _isLoadingRoute,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _TopRouteControls(
                    pickup: widget.initialPickup,
                    destination: widget.initialDestination,
                    onClose: _close,
                    onEditRoute: _editRoute,
                    onAddStop: () => _editRoute(showStop: true),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _RideSelectionPanel(
                    selectedRide: _selectedRide,
                    selectedPayment: _selectedPayment,
                    onRideSelected: _selectRide,
                    onContinue: _continueToPickup,
                    onPaymentTap: _openPaymentOptions,
                    route: _route,
                    isLoadingRoute: _isLoadingRoute,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SelectRideMap extends StatelessWidget {
  const _SelectRideMap({
    required this.route,
    required this.isLoadingRoute,
  });

  final CitirideRoute? route;
  final bool isLoadingRoute;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CitirideLiveRouteMap(
          route: route,
          showCars: false,
          showPickupPulse: true,
          fallbackSemanticsLabel: 'Select ride map background',
          routeSemanticsLabel: 'Ride route direction',
        ),
        if (isLoadingRoute)
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + 108,
            child: const Center(child: _RouteLoadingChip()),
          ),
      ],
    );
  }
}

class _RouteLoadingChip extends StatelessWidget {
  const _RouteLoadingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.citirideBlack.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.32)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          'Calculating route...',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _TopRouteControls extends StatelessWidget {
  const _TopRouteControls({
    required this.pickup,
    required this.destination,
    required this.onClose,
    required this.onEditRoute,
    required this.onAddStop,
  });

  final String pickup;
  final String destination;
  final VoidCallback onClose;
  final VoidCallback onEditRoute;
  final VoidCallback onAddStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(onTap: onClose, icon: Icons.close, semantics: 'Close'),
        const SizedBox(width: 4),
        Expanded(
          child: _RouteSummaryPill(
            pickup: pickup,
            destination: destination,
            onTap: onEditRoute,
          ),
        ),
        const SizedBox(width: 4),
        _SelectRideAddStopButton(onTap: onAddStop),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.onTap,
    required this.icon,
    required this.semantics,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        key: const ValueKey('select-ride-close'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 1.5),
          ),
          child: Icon(icon, color: AppColors.white, size: 25),
        ),
      ),
    );
  }
}

class _RouteSummaryPill extends StatelessWidget {
  const _RouteSummaryPill({
    required this.pickup,
    required this.destination,
    required this.onTap,
  });

  final String pickup;
  final String destination;
  final VoidCallback onTap;

  String get _displayPickup {
    final value = pickup.trim();
    return value.isEmpty ? 'Current Location' : value;
  }

  String get _displayDestination {
    final value = destination.trim();
    return value.isEmpty ? 'Ring Road Bus Terminal' : value;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Edit route',
      child: GestureDetector(
        key: const ValueKey('select-ride-route-summary'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.white),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _displayPickup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.citirideYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.arrow_forward,
                color: AppColors.citirideYellow,
                size: 18,
              ),
              SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  _displayDestination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
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

class _SelectRideAddStopButton extends StatelessWidget {
  const _SelectRideAddStopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add stop',
      child: GestureDetector(
        key: const ValueKey('select-ride-add-stop'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 85,
            maxWidth: 85,
            minHeight: 139,
            maxHeight: 139,
            child: Transform.translate(
              offset: Offset(-25, -4),
              child: CompatibleSvgPicture.asset(
                'assets/images/add_stop icon.svg',
                width: 85,
                height: 139,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RideSelectionPanel extends StatelessWidget {
  const _RideSelectionPanel({
    required this.selectedRide,
    required this.selectedPayment,
    required this.onRideSelected,
    required this.onContinue,
    required this.onPaymentTap,
    required this.route,
    required this.isLoadingRoute,
  });

  final _RideOption selectedRide;
  final _PaymentMethod selectedPayment;
  final ValueChanged<_RideOption> onRideSelected;
  final VoidCallback onContinue;
  final VoidCallback onPaymentTap;
  final CitirideRoute? route;
  final bool isLoadingRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        19,
        0,
        19,
        MediaQuery.paddingOf(context).bottom + 18,
      ),
      decoration: const BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 9),
          _RideCard(
            key: const ValueKey('ride-card-regular'),
            option: _RideOption.regular,
            isSelected: selectedRide == _RideOption.regular,
            title: 'Regular',
            subtitle: 'Mid-size Cars',
            time:
                route?.durationText ??
                (isLoadingRoute ? 'Calculating' : 'Route pending'),
            seats: '4',
            price: fareLabelForRoute(
              tier: CitirideRideTier.regular,
              route: route,
              isLoadingRoute: isLoadingRoute,
            ),
            carAsset: 'assets/images/Car img - select ride.svg',
            onTap: () => onRideSelected(_RideOption.regular),
          ),
          const SizedBox(height: 14),
          _RideCard(
            key: const ValueKey('ride-card-vip'),
            option: _RideOption.vip,
            isSelected: selectedRide == _RideOption.vip,
            title: 'VIP',
            subtitle: 'Modern Car Models',
            time:
                _vipDurationText(route) ??
                (isLoadingRoute ? 'Calculating' : 'Route pending'),
            seats: '2',
            price: fareLabelForRoute(
              tier: CitirideRideTier.vip,
              route: route,
              isLoadingRoute: isLoadingRoute,
            ),
            carAsset: 'assets/images/car image - VIP.svg',
            onTap: () => onRideSelected(_RideOption.vip),
          ),
          const SizedBox(height: 26),
          const Text(
            'Select payment Options',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _PaymentOption(selectedPayment: selectedPayment, onTap: onPaymentTap),
          const Spacer(),
          _ContinueButton(onPressed: onContinue),
        ],
      ),
    );
  }
}

String? _vipDurationText(CitirideRoute? route) {
  if (route == null) {
    return null;
  }

  final minutes = math.max(1, (route.duration.inMinutes * 0.82).ceil());
  return minutes == 1 ? '1 min' : '$minutes mins';
}

class _RideCard extends StatelessWidget {
  const _RideCard({
    super.key,
    required this.option,
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.seats,
    required this.price,
    required this.carAsset,
    required this.onTap,
  });

  final _RideOption option;
  final bool isSelected;
  final String title;
  final String subtitle;
  final String time;
  final String seats;
  final String price;
  final String carAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title ride option',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey('ride-card-container-${option.name}'),
          duration: const Duration(milliseconds: 160),
          height: 73,
          padding: const EdgeInsets.fromLTRB(9, 7, 10, 7),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B2B),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: AppColors.citirideYellow, width: 2)
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 79,
                height: 47,
                child: CompatibleSvgPicture.asset(
                  carAsset,
                  fit: BoxFit.contain,
                  semanticsLabel: '$title car',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9C9C9C),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        height: 1.1,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          time,
                          style: const TextStyle(
                            color: Color(0xFF9C9C9C),
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(width: 13),
                        const Icon(
                          Icons.people_alt,
                          color: Color(0xFF9C9C9C),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          seats,
                          style: const TextStyle(
                            color: Color(0xFF9C9C9C),
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
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      color: AppColors.citirideYellow,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({required this.selectedPayment, required this.onTap});

  final _PaymentMethod selectedPayment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWallet = selectedPayment == _PaymentMethod.wallet;
    final iconAsset = isWallet
        ? 'assets/images/wallet icon.svg'
        : 'assets/images/cash_icon - select ride.svg';
    final icon = CompatibleSvgPicture.asset(iconAsset, fit: BoxFit.contain);
    final title = isWallet ? 'CitiRide Wallet' : 'Cash';
    final subtitle = isWallet ? 'Bal: \u20A63,000' : 'Pay with cash';

    return Semantics(
      label: '$title payment',
      button: true,
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('select-ride-payment-option'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: isWallet
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF2C2D36),
                        BlendMode.srcIn,
                      ),
                      child: icon,
                    )
                  : icon,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8F8F8F),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.2),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 49,
      child: FilledButton(
        onPressed: onPressed,
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
        child: const Text('Continue'),
      ),
    );
  }
}
