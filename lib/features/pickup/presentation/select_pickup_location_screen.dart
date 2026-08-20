import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/location/citiride_place.dart';
import '../../../core/location/citiride_route.dart';
import '../../../core/location/citiride_route_service.dart';
import '../../../core/location/live_location_service.dart';
import '../../../core/location/places_service.dart';
import '../../../core/location/route_query.dart';
import '../../../shared/widgets/citiride_live_route_map.dart';
import '../../../shared/widgets/citiride_location_status_pulse.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../../shared/widgets/location_search_empty_state.dart';

class SelectPickupLocationScreen extends StatefulWidget {
  const SelectPickupLocationScreen({
    super.key,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
    this.initialPickup = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
  });

  final String rideType;
  final String paymentMethod;
  final String initialPickup;
  final String initialDestination;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;

  @override
  State<SelectPickupLocationScreen> createState() =>
      _SelectPickupLocationScreenState();
}

class _SelectPickupLocationScreenState
    extends State<SelectPickupLocationScreen> {
  final _locationService = const LiveLocationService();
  final _routeService = CitirideRouteService();
  final _placesService = CitiridePlacesService();
  StreamSubscription<LatLng>? _locationSubscription;
  String _pickupLocation = '';
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  LatLng? _currentLatLng;
  LatLng? _mapPickupCandidate;
  bool _isMovingPickupFromMap = false;
  /// After the rider pans the map, keep the camera still so the center pin
  /// stays over the place they chose (don't snap back via route fitBounds).
  bool _holdCameraOnUserPickup = false;
  CitirideRoute? _route;
  bool _isLoadingRoute = false;
  int _routeLoadGeneration = 0;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = widget.initialPickup;
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _loadRoute();
    if (!_isRunningWidgetTest) {
      _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    final currentLocation = await _locationService
        .currentLatLng(requestIfDenied: true)
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
    if (currentLocation != null) {
      _applyCurrentLocation(currentLocation, setPickupIfDefault: true);
    }

    _locationSubscription = _locationService
        .watchLatLng(requestIfDenied: true)
        .listen((location) {
          _applyCurrentLocation(location, setPickupIfDefault: false);
        });
  }

  void _applyCurrentLocation(
    LatLng location, {
    required bool setPickupIfDefault,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      _currentLatLng = location;
      if (setPickupIfDefault &&
          _pickupLatLng == null &&
          (_pickupLocation.trim().isEmpty ||
              _pickupLocation == 'Lagos Street')) {
        _pickupLatLng = location;
        _pickupLocation = 'Current Location';
        _loadRoute();
      }
    });
  }

  Future<void> _loadRoute() async {
    final pickup = _pickupLatLng;
    final destination = _destinationLatLng;
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

  bool get _isVip => widget.rideType == 'vip';
  String get _rideLabel => _isVip ? 'Modern Car Models' : 'Mid-size Car';
  String get _ridePrice => _isVip ? '\u20A67,500' : '\u20A63,500';

  void _close() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/select-ride');
  }

  void _editRoute({bool showStop = false}) {
    final routeUri = Uri(
      path: '/route',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
        'pickup': _pickupLocation,
        'destination': widget.initialDestination,
        ...latLngToQuery('pickup', _pickupLatLng),
        ...latLngToQuery('destination', _destinationLatLng),
        if (showStop) 'showStop': 'true',
      },
    );
    context.push(routeUri.toString());
  }

  void _selectPickupPlace(CitiridePlace place, {bool holdCamera = false}) {
    setState(() {
      _pickupLocation = place.displayText;
      _pickupLatLng = place.location ?? _pickupLatLng;
      if (holdCamera) {
        _holdCameraOnUserPickup = true;
      }
    });
    _loadRoute();
  }

  Future<void> _setPickupFromMap(LatLng location) async {
    final label = await _placesService
        .reverseGeocodeLabel(location)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);

    if (!mounted) {
      return;
    }

    _selectPickupPlace(
      CitiridePlace(
        title: label?.trim().isNotEmpty == true ? label!.trim() : 'Dropped pin',
        subtitle: label?.trim().isNotEmpty == true
            ? 'Pinned pickup point'
            : 'Move the map to refine pickup',
        location: location,
      ),
      holdCamera: true,
    );
  }

  Future<void> _useCurrentLocation() async {
    final currentLocation = await _locationService.currentLatLng();
    if (!mounted) {
      return;
    }

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to pick your current location.')),
      );
      return;
    }

    setState(() => _holdCameraOnUserPickup = false);
    _selectPickupPlace(
      CitiridePlace(
        title: 'Current Location',
        subtitle: 'Picked from your device GPS',
        location: currentLocation,
        isCurrentLocation: true,
      ),
    );
  }

  void _beginPickupMapMove() {
    setState(() {
      _isMovingPickupFromMap = true;
      _holdCameraOnUserPickup = true;
      _mapPickupCandidate = null;
    });
  }

  void _handlePickupCameraMove(CameraPosition position) {
    if (!_isMovingPickupFromMap) {
      return;
    }

    _mapPickupCandidate = position.target;
  }

  void _handlePickupCameraIdle() {
    if (!_isMovingPickupFromMap) {
      return;
    }

    _isMovingPickupFromMap = false;
    final location = _mapPickupCandidate;
    _mapPickupCandidate = null;
    if (location != null) {
      unawaited(_setPickupFromMap(location));
    }
  }

  void _confirmOrder() {
    final lookingUri = Uri(
      path: '/looking-for-driver',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
        'pickup': _pickupLocation,
        'destination': widget.initialDestination,
        ...latLngToQuery('pickup', _pickupLatLng),
        ...latLngToQuery('destination', _destinationLatLng),
      },
    );
    context.push(lookingUri.toString());
  }

  Future<void> _showPickupSearch() async {
    final selectedLocation = await showModalBottomSheet<CitiridePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) {
        return PickupSearchSheet(
          initialLocation: _pickupLocation,
          locationBias: _pickupLatLng ?? _currentLatLng,
        );
      },
    );

    if (selectedLocation == null || !mounted) {
      return;
    }

    setState(() => _holdCameraOnUserPickup = false);
    _selectPickupPlace(selectedLocation);
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
              260.0,
              math.max(236.0, constraints.maxHeight * 0.29),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _PickupMap(
                    route: _route,
                    isLoadingRoute: _isLoadingRoute,
                    fitRouteInView: !_holdCameraOnUserPickup,
                    onMapTap: (location) =>
                        unawaited(_setPickupFromMap(location)),
                    onMapGestureStart: _beginPickupMapMove,
                    onCameraMove: _handlePickupCameraMove,
                    onCameraIdle: _handlePickupCameraIdle,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _PickupTopControls(
                    pickupLocation: _pickupLocation,
                    destination: widget.initialDestination,
                    onClose: _close,
                    onEditRoute: _editRoute,
                    onAddStop: () => _editRoute(showStop: true),
                  ),
                ),
                Positioned(
                  right: 13,
                  bottom: panelHeight + 22,
                  child: _MyLocationButton(onTap: _useCurrentLocation),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _PickupLocationPanel(
                    pickupLocation: _pickupLocation,
                    rideLabel: _rideLabel,
                    ridePrice: _ridePrice,
                    onSearchTap: _showPickupSearch,
                    onConfirmOrder: _confirmOrder,
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

class _PickupMap extends StatelessWidget {
  const _PickupMap({
    required this.route,
    required this.isLoadingRoute,
    this.fitRouteInView = true,
    this.onMapTap,
    this.onMapGestureStart,
    this.onCameraMove,
    this.onCameraIdle,
  });

  final CitirideRoute? route;
  final bool isLoadingRoute;
  final bool fitRouteInView;
  final ValueChanged<LatLng>? onMapTap;
  final VoidCallback? onMapGestureStart;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraIdle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => onMapGestureStart?.call(),
          child: CitirideLiveRouteMap(
            route: route,
            showPickupMarker: false,
            fitRouteInView: fitRouteInView,
            fallbackSemanticsLabel: 'Pickup map background',
            routeSemanticsLabel: 'Pickup route direction',
            onMapTap: onMapTap,
            onCameraMove: onCameraMove,
            onCameraIdle: onCameraIdle,
          ),
        ),
        const IgnorePointer(
          child: Center(
            child: CitirideLocationStatusPulse(
              size: 112,
              iconSize: 68,
              semanticsLabel: 'Movable pickup location',
            ),
          ),
        ),
        if (isLoadingRoute)
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + 108,
            child: const Center(child: _PickupRouteLoadingChip()),
          ),
      ],
    );
  }
}

class _PickupRouteLoadingChip extends StatelessWidget {
  const _PickupRouteLoadingChip();

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
          'Updating route...',
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

class _PickupTopControls extends StatelessWidget {
  const _PickupTopControls({
    required this.pickupLocation,
    required this.destination,
    required this.onClose,
    required this.onEditRoute,
    required this.onAddStop,
  });

  final String pickupLocation;
  final String destination;
  final VoidCallback onClose;
  final VoidCallback onEditRoute;
  final VoidCallback onAddStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PickupCircleButton(
          onTap: onClose,
          icon: Icons.close,
          semantics: 'Close',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _PickupRouteSummaryPill(
            pickupLocation: pickupLocation,
            destination: destination,
            onTap: onEditRoute,
          ),
        ),
        const SizedBox(width: 4),
        _PickupAddStopButton(onTap: onAddStop),
      ],
    );
  }
}

class _PickupCircleButton extends StatelessWidget {
  const _PickupCircleButton({
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

class _PickupRouteSummaryPill extends StatelessWidget {
  const _PickupRouteSummaryPill({
    required this.pickupLocation,
    required this.destination,
    required this.onTap,
  });

  final String pickupLocation;
  final String destination;
  final VoidCallback onTap;

  String get _displayPickup {
    final value = pickupLocation.trim();
    return value.isEmpty ? 'Current Location' : value;
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
                style: const TextStyle(
                  color: AppColors.citirideYellow,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward,
              color: AppColors.citirideYellow,
              size: 18,
            ),
            const SizedBox(width: 8),
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

class _PickupAddStopButton extends StatelessWidget {
  const _PickupAddStopButton({required this.onTap});

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

class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 49,
        height: 49,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location,
          color: AppColors.citirideBlack,
          size: 24,
        ),
      ),
    );
  }
}

class _PickupLocationPanel extends StatelessWidget {
  const _PickupLocationPanel({
    required this.pickupLocation,
    required this.rideLabel,
    required this.ridePrice,
    required this.onSearchTap,
    required this.onConfirmOrder,
  });

  final String pickupLocation;
  final String rideLabel;
  final String ridePrice;
  final VoidCallback onSearchTap;
  final VoidCallback onConfirmOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
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
          const SizedBox(height: 18),
          const Center(
            child: Text(
              'Select pickup location',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  pickupLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
              GestureDetector(
                key: const ValueKey('pickup-search-button'),
                behavior: HitTestBehavior.opaque,
                onTap: onSearchTap,
                child: const SizedBox(
                  width: 34,
                  height: 34,
                  child: CompatibleSvgPicture.asset(
                    'assets/images/Search Icon.svg',
                    fit: BoxFit.contain,
                    semanticsLabel: 'Search pickup location',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Text(
                rideLabel,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 19),
              Text(
                ridePrice,
                style: const TextStyle(
                  color: AppColors.citirideYellow,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 49,
            child: FilledButton(
              onPressed: onConfirmOrder,
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
              child: const Text('Confirm Order'),
            ),
          ),
        ],
      ),
    );
  }
}

class PickupSearchSheet extends StatefulWidget {
  const PickupSearchSheet({
    super.key,
    required this.initialLocation,
    this.locationBias,
  });

  final String initialLocation;
  final LatLng? locationBias;

  @override
  State<PickupSearchSheet> createState() => _PickupSearchSheetState();
}

class _PickupSearchSheetState extends State<PickupSearchSheet> {
  final _placesService = CitiridePlacesService();
  final _locationService = const LiveLocationService();
  late final TextEditingController _controller;
  Timer? _searchDebounce;
  List<CitiridePlace> _suggestions = const [];
  bool _isSearching = false;
  bool _hasSearched = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLocation);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _suggestions = _placesService.defaultPlaces();
    _controller.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.removeListener(_scheduleSearch);
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final query = _controller.text.trim();
    _searchDebounce?.cancel();

    if (query.length < 2) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _suggestions = _placesService.defaultPlaces();
      });
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      final results = await _placesService.autocomplete(
        query,
        locationBias: widget.locationBias,
      );
      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  void _submitTypedLocation(String value) {
    final location = value.trim();
    if (location.isEmpty) {
      return;
    }

    Navigator.of(context).pop(CitiridePlace(title: location));
  }

  Future<void> _submitMyLocation() async {
    final currentLocation = await _locationService.currentLatLng();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      CitiridePlace(
        title: currentLocation == null ? 'My Location' : 'Current Location',
        subtitle: currentLocation == null
            ? null
            : 'Picked from your device GPS',
        location: currentLocation,
        isCurrentLocation: true,
      ),
    );
  }

  Future<void> _submitSuggestion(CitiridePlace suggestion) async {
    final resolvedSuggestion = await _placesService.resolve(suggestion);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(resolvedSuggestion);
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final visibleSuggestions = _suggestions
        .where((suggestion) => !_isExactMatch(suggestion, query))
        .toList(growable: false);

    return FractionallySizedBox(
      heightFactor: 0.84,
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          9,
          20,
          MediaQuery.paddingOf(context).bottom + 24,
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
            const SizedBox(height: 13),
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.white),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 17),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CompatibleSvgPicture.asset(
                      'assets/images/Search Icon.svg',
                      fit: BoxFit.contain,
                      semanticsLabel: 'Pickup search icon',
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('pickup-search-field'),
                      controller: _controller,
                      autofocus: true,
                      cursorColor: AppColors.citirideYellow,
                      keyboardAppearance: Brightness.dark,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _submitTypedLocation,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Search your pickup location',
                        hintStyle: TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _PickupSearchResult(
              title: 'My Location',
              onTap: _submitMyLocation,
              isMyLocation: true,
            ),
            const SizedBox(height: 18),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _isSearching
                    ? const _PickupSearchLoading()
                    : _hasSearched && _suggestions.isEmpty
                    ? LocationSearchEmptyState(query: query)
                    : ListView.separated(
                        key: ValueKey(
                          'pickup-results-${_hasSearched ? query : 'default'}',
                        ),
                        padding: EdgeInsets.zero,
                        itemCount: visibleSuggestions.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final suggestion = visibleSuggestions[index];
                          return _PickupSearchResult(
                            title: suggestion.title,
                            subtitle: suggestion.subtitle,
                            onTap: () => _submitSuggestion(suggestion),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isExactMatch(CitiridePlace suggestion, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return suggestion.title.trim().toLowerCase() == normalizedQuery ||
        suggestion.displayText.trim().toLowerCase() == normalizedQuery;
  }
}

class _PickupSearchLoading extends StatelessWidget {
  const _PickupSearchLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.citirideYellow,
        ),
      ),
    );
  }
}

class _PickupSearchResult extends StatelessWidget {
  const _PickupSearchResult({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isMyLocation = false,
  });

  final String title;
  final String? subtitle;
  final bool isMyLocation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('pickup-result-${title.trim().toLowerCase()}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: isMyLocation
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E8E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.my_location,
                      color: Color(0xFF2C2D36),
                      size: 18,
                    ),
                  )
                : const CompatibleSvgPicture.asset(
                    'assets/images/Location_Icon.svg',
                    fit: BoxFit.contain,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8F8F8F),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
