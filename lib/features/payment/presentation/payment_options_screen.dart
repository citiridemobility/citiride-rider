import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/location/citiride_route.dart';
import '../../../core/location/citiride_route_service.dart';
import '../../../core/location/route_query.dart';
import '../../../shared/widgets/citiride_live_route_map.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../wallet/presentation/wallet_enrollment_store.dart';

enum _RideOption { regular, vip }

enum _PaymentMethod { cash, wallet }

class PaymentOptionsScreen extends StatefulWidget {
  const PaymentOptionsScreen({
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
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen> {
  final _routeService = CitirideRouteService();
  late _RideOption _selectedRide;
  late _PaymentMethod _selectedPayment;
  CitirideRoute? _route;
  bool _isLoadingRoute = false;
  int _routeLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedRide = widget.initialRide == 'vip'
        ? _RideOption.vip
        : _RideOption.regular;
    _selectedPayment = widget.initialPayment == 'wallet' &&
            WalletEnrollmentStore.instance.isEnrolled
        ? _PaymentMethod.wallet
        : _PaymentMethod.cash;
    _loadRoute();
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

  void _selectPayment(_PaymentMethod payment) {
    if (payment == _PaymentMethod.wallet &&
        !WalletEnrollmentStore.instance.isEnrolled) {
      return;
    }

    setState(() {
      _selectedPayment = payment;
    });
  }

  void _activateWallet() {
    context.push('/wallet-sign-up');
  }

  void _returnToSelectRide() {
    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: _routeQueryParameters(),
    );
    context.go(selectRideUri.toString());
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

    context.go('/select-ride');
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
              520.0,
              math.max(470.0, constraints.maxHeight * 0.615),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _PaymentMap(
                    route: _route,
                    isLoadingRoute: _isLoadingRoute,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _PaymentTopControls(
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
                  child: _PaymentOptionsPanel(
                    selectedRide: _selectedRide,
                    selectedPayment: _selectedPayment,
                    walletEnrolled: WalletEnrollmentStore.instance.isEnrolled,
                    onRideSelected: _selectRide,
                    onPaymentSelected: _selectPayment,
                    onActivateWallet: _activateWallet,
                    onContinue: _returnToSelectRide,
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

class _PaymentMap extends StatelessWidget {
  const _PaymentMap({
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
          fallbackSemanticsLabel: 'Payment map background',
          routeSemanticsLabel: 'Payment route direction',
        ),
        if (isLoadingRoute)
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + 108,
            child: const Center(child: _PaymentRouteLoadingChip()),
          ),
      ],
    );
  }
}

class _PaymentRouteLoadingChip extends StatelessWidget {
  const _PaymentRouteLoadingChip();

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

class _PaymentTopControls extends StatelessWidget {
  const _PaymentTopControls({
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
        _PaymentCircleButton(
          onTap: onClose,
          icon: Icons.close,
          semantics: 'Close',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _PaymentRouteSummaryPill(
            pickup: pickup,
            destination: destination,
            onTap: onEditRoute,
          ),
        ),
        const SizedBox(width: 4),
        _PaymentAddStopButton(onTap: onAddStop),
      ],
    );
  }
}

class _PaymentCircleButton extends StatelessWidget {
  const _PaymentCircleButton({
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

class _PaymentRouteSummaryPill extends StatelessWidget {
  const _PaymentRouteSummaryPill({
    required this.pickup,
    required this.destination,
    required this.onTap,
  });

  final String pickup;
  final String destination;
  final VoidCallback onTap;

  String get _displayPickup {
    final value = pickup.trim();
    if (value.isEmpty || value == 'Lagos Street') {
      return 'Lagos St.';
    }
    return value;
  }

  String get _displayDestination {
    final value = destination.trim();
    return value.isEmpty ? 'Ring Road Bus Terminal' : value;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}

class _PaymentAddStopButton extends StatelessWidget {
  const _PaymentAddStopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}

class _PaymentOptionsPanel extends StatelessWidget {
  const _PaymentOptionsPanel({
    required this.selectedRide,
    required this.selectedPayment,
    required this.walletEnrolled,
    required this.onRideSelected,
    required this.onPaymentSelected,
    required this.onActivateWallet,
    required this.onContinue,
    required this.route,
    required this.isLoadingRoute,
  });

  final _RideOption selectedRide;
  final _PaymentMethod selectedPayment;
  final bool walletEnrolled;
  final ValueChanged<_RideOption> onRideSelected;
  final ValueChanged<_PaymentMethod> onPaymentSelected;
  final VoidCallback onActivateWallet;
  final VoidCallback onContinue;
  final CitirideRoute? route;
  final bool isLoadingRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        19,
        9,
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
          Center(
            child: Container(
              width: 49,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4EA),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PaymentRouteMetrics(route: route, isLoadingRoute: isLoadingRoute),
          const SizedBox(height: 9),
          _PaymentRideCard(
            key: const ValueKey('payment-ride-card-regular'),
            option: _RideOption.regular,
            isSelected: selectedRide == _RideOption.regular,
            title: 'Regular',
            subtitle: 'Mid-size Cars',
            time:
                route?.durationText ??
                (isLoadingRoute ? 'Calculating' : 'Route pending'),
            seats: '4',
            price: '\u20A63,500',
            oldPrice: '\u20A64,500',
            carAsset: 'assets/images/Car img - select ride.svg',
            onTap: () => onRideSelected(_RideOption.regular),
          ),
          const SizedBox(height: 14),
          _PaymentRideCard(
            key: const ValueKey('payment-ride-card-vip'),
            option: _RideOption.vip,
            isSelected: selectedRide == _RideOption.vip,
            title: 'VIP',
            subtitle: 'Modern Car Models',
            time:
                _paymentVipDurationText(route) ??
                (isLoadingRoute ? 'Calculating' : 'Route pending'),
            seats: '2',
            price: '\u20A67,500',
            oldPrice: '\u20A69,500',
            carAsset: 'assets/images/car image - VIP.svg',
            onTap: () => onRideSelected(_RideOption.vip),
          ),
          const SizedBox(height: 21),
          const Text(
            'Payment Options',
            style: TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 17),
          _PaymentMethodRow(
            key: const ValueKey('payment-method-cash'),
            iconAsset: 'assets/images/cash icon.svg',
            title: 'Cash',
            subtitle: 'Pay with cash',
            isSelected: selectedPayment == _PaymentMethod.cash,
            onTap: () => onPaymentSelected(_PaymentMethod.cash),
          ),
          const SizedBox(height: 19),
          if (walletEnrolled)
            _PaymentMethodRow(
              key: const ValueKey('payment-method-wallet'),
              iconAsset: 'assets/images/wallet icon.svg',
              title: 'CitiRide Wallet',
              subtitle: 'Bal: \u20A63,000',
              isSelected: selectedPayment == _PaymentMethod.wallet,
              showTopUp: true,
              onTap: () => onPaymentSelected(_PaymentMethod.wallet),
            )
          else
            _PaymentMethodRow(
              key: const ValueKey('payment-method-activate-wallet'),
              iconAsset: 'assets/images/wallet icon.svg',
              title: 'Activate wallet',
              subtitle: 'Optional • Set up CitiRide Wallet',
              isSelected: false,
              actionLabel: 'Activate',
              onTap: onActivateWallet,
            ),
          const Spacer(),
          _PaymentContinueButton(onPressed: onContinue),
        ],
      ),
    );
  }
}

class _PaymentRouteMetrics extends StatelessWidget {
  const _PaymentRouteMetrics({
    required this.route,
    required this.isLoadingRoute,
  });

  final CitirideRoute? route;
  final bool isLoadingRoute;

  @override
  Widget build(BuildContext context) {
    final activeRoute = route;
    final text = activeRoute == null
        ? (isLoadingRoute
              ? 'Calculating distance and ETA'
              : 'Select valid route points')
        : '${activeRoute.distanceText} trip - ${activeRoute.durationText} to destination';

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: route == null
            ? const Color(0xFF8F8F8F)
            : AppColors.citirideYellow,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

String? _paymentVipDurationText(CitirideRoute? route) {
  if (route == null) {
    return null;
  }

  final minutes = math.max(1, (route.duration.inMinutes * 0.82).ceil());
  return minutes == 1 ? '1 min' : '$minutes mins';
}

class _PaymentRideCard extends StatelessWidget {
  const _PaymentRideCard({
    super.key,
    required this.option,
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.seats,
    required this.price,
    required this.oldPrice,
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
  final String oldPrice;
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
          key: ValueKey('payment-ride-card-container-${option.name}'),
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
                  const SizedBox(height: 7),
                  Text(
                    oldPrice,
                    style: const TextStyle(
                      color: Color(0xFF8F8F8F),
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      height: 1,
                      letterSpacing: 0,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Color(0xFF8F8F8F),
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

class _PaymentMethodRow extends StatelessWidget {
  const _PaymentMethodRow({
    super.key,
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.showTopUp = false,
    this.actionLabel,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool showTopUp;
  final String? actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CompatibleSvgPicture.asset(
              iconAsset,
              fit: BoxFit.contain,
              semanticsLabel: '$title icon',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (showTopUp || actionLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.citirideYellow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          actionLabel ?? 'Top up wallet',
                          style: const TextStyle(
                            color: AppColors.citirideBlack,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (actionLabel == null)
            _PaymentRadio(isSelected: isSelected)
          else
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF8F8F8F),
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _PaymentRadio extends StatelessWidget {
  const _PaymentRadio({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? AppColors.citirideYellow
              : const Color(0xFF9C9C9C),
          width: 1.4,
        ),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: isSelected ? 9 : 0,
          height: isSelected ? 9 : 0,
          decoration: const BoxDecoration(
            color: AppColors.citirideYellow,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _PaymentContinueButton extends StatelessWidget {
  const _PaymentContinueButton({required this.onPressed});

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
