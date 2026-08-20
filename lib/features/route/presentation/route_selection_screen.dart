import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/maps/google_maps_config.dart';
import '../../../core/location/citiride_place.dart';
import '../../../core/location/live_location_service.dart';
import '../../../core/location/places_service.dart';
import '../../../core/location/route_query.dart';
import '../../../shared/widgets/citiride_google_map.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../../../shared/widgets/location_search_empty_state.dart';

enum _RouteSearchTarget { pickup, stop, destination }

class RouteSelectionScreen extends StatefulWidget {
  const RouteSelectionScreen({
    super.key,
    this.initialLocation = 'Current Location',
    this.initialDestination = '',
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.showStopFieldInitially = false,
    this.isEditingDestinations = false,
    this.returnRideType = 'regular',
    this.returnPayment = 'cash',
    this.returnTo = 'driver-found',
  });

  final String initialLocation;
  final String initialDestination;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final bool showStopFieldInitially;
  final bool isEditingDestinations;
  final String returnRideType;
  final String returnPayment;
  final String returnTo;

  @override
  State<RouteSelectionScreen> createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen> {
  final _placesService = CitiridePlacesService();
  final _locationService = const LiveLocationService();
  Timer? _searchDebounce;
  LatLng? _locationBias;
  LatLng? _pickupLatLng;
  LatLng? _stopLatLng;
  LatLng? _destinationLatLng;
  String? _pickupLatLngText;
  String? _stopLatLngText;
  String? _destinationLatLngText;
  _RouteSearchTarget? _activeSearchTarget;
  List<CitiridePlace> _placeSuggestions = const [];
  bool _isSearchingPlaces = false;
  bool _hasPlaceSearch = false;
  bool _isResolvingRoute = false;
  int _searchGeneration = 0;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  late final TextEditingController _locationController;
  late final TextEditingController _stopController;
  late final TextEditingController _destinationController;
  late final FocusNode _locationFocusNode;
  late final FocusNode _stopFocusNode;
  late final FocusNode _destinationFocusNode;

  late bool _showStopField;

  bool get _canRequestRide {
    return !_isResolvingRoute &&
        _locationController.text.trim().isNotEmpty &&
        _destinationController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController(text: widget.initialLocation);
    _stopController = TextEditingController();
    _destinationController = TextEditingController(
      text: widget.initialDestination,
    );
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _pickupLatLngText = _pickupLatLng == null
        ? null
        : _locationController.text.trim();
    _destinationLatLngText = _destinationLatLng == null
        ? null
        : _destinationController.text.trim();
    _showStopField = widget.showStopFieldInitially;
    _locationFocusNode = FocusNode();
    _stopFocusNode = FocusNode();
    _destinationFocusNode = FocusNode();

    _locationController.addListener(_handleFieldChanged);
    _stopController.addListener(_handleFieldChanged);
    _destinationController.addListener(_handleFieldChanged);
    _locationFocusNode.addListener(() {
      _handleFocusChanged(_RouteSearchTarget.pickup, _locationFocusNode);
    });
    _stopFocusNode.addListener(() {
      _handleFocusChanged(_RouteSearchTarget.stop, _stopFocusNode);
    });
    _destinationFocusNode.addListener(() {
      _handleFocusChanged(
        _RouteSearchTarget.destination,
        _destinationFocusNode,
      );
    });
    if (!_isRunningWidgetTest) {
      _loadLocationBias();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _locationController.removeListener(_handleFieldChanged);
    _stopController.removeListener(_handleFieldChanged);
    _destinationController.removeListener(_handleFieldChanged);
    _locationController.dispose();
    _stopController.dispose();
    _destinationController.dispose();
    _locationFocusNode.dispose();
    _stopFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLocationBias() async {
    final currentLocation = await _locationService
        .currentLatLng(requestIfDenied: true)
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
    _locationBias = currentLocation ?? widget.initialPickupLatLng;

    if (!mounted) {
      return;
    }

    final resolvedLocation = _locationBias;
    if (resolvedLocation == null) {
      return;
    }

    final pickupText = _locationController.text.trim();
    final shouldUseLiveLocation =
        pickupText.isEmpty ||
        pickupText == 'Current Location' ||
        pickupText == 'My location' ||
        pickupText == 'Set location' ||
        pickupText == 'Locating...' ||
        pickupText == 'Lagos Street';

    if (shouldUseLiveLocation) {
      final label =
          await _placesService
              .reverseGeocodeLabel(resolvedLocation)
              .timeout(const Duration(seconds: 8), onTimeout: () => null) ??
          'My location';
      if (!mounted) {
        return;
      }

      _locationController.text = label;
      _setLatLngForTarget(_RouteSearchTarget.pickup, resolvedLocation, label);
      setState(() {});
    }
  }

  void _handleFieldChanged() {
    _clearLatLngWhenTextChanges();
    setState(() {});
    _schedulePlaceSearch();
  }

  void _clearLatLngWhenTextChanges() {
    if (_pickupLatLngText != null &&
        _locationController.text.trim() != _pickupLatLngText) {
      _pickupLatLng = null;
      _pickupLatLngText = null;
    }
    if (_stopLatLngText != null &&
        _stopController.text.trim() != _stopLatLngText) {
      _stopLatLng = null;
      _stopLatLngText = null;
    }
    if (_destinationLatLngText != null &&
        _destinationController.text.trim() != _destinationLatLngText) {
      _destinationLatLng = null;
      _destinationLatLngText = null;
    }
  }

  void _handleFocusChanged(_RouteSearchTarget target, FocusNode focusNode) {
    if (!focusNode.hasFocus) {
      return;
    }

    setState(() {
      _activeSearchTarget = target;
    });
    _schedulePlaceSearch();
  }

  TextEditingController _controllerForTarget(_RouteSearchTarget target) {
    return switch (target) {
      _RouteSearchTarget.pickup => _locationController,
      _RouteSearchTarget.stop => _stopController,
      _RouteSearchTarget.destination => _destinationController,
    };
  }

  String get _activeSearchQuery {
    final target = _activeSearchTarget;
    if (target == null) {
      return '';
    }
    return _controllerForTarget(target).text.trim();
  }

  void _schedulePlaceSearch() {
    final target = _activeSearchTarget;
    _searchDebounce?.cancel();

    if (target == null) {
      return;
    }

    final query = _controllerForTarget(target).text.trim();
    if (query.length < 2 ||
        query == 'Current Location' ||
        query == 'My location' ||
        query == 'Set location' ||
        query == 'Locating...') {
      setState(() {
        _isSearchingPlaces = false;
        _hasPlaceSearch = false;
        _placeSuggestions = const [];
      });
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _isSearchingPlaces = true;
      _hasPlaceSearch = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      final suggestions = await _placesService.autocomplete(
        query,
        locationBias: _locationBias,
      );
      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _placeSuggestions = suggestions;
        _isSearchingPlaces = false;
      });
    });
  }

  Future<void> _selectDefaultPlaceSuggestion(CitiridePlace suggestion) async {
    if (_activeSearchTarget == null) {
      setState(() {
        _activeSearchTarget = _RouteSearchTarget.destination;
      });
    }
    await _selectPlaceSuggestion(suggestion);
  }

  Future<void> _selectPlaceSuggestion(CitiridePlace suggestion) async {
    final target = _activeSearchTarget;
    if (target == null) {
      return;
    }

    final resolvedSuggestion = await _placesService.resolve(suggestion);
    if (!mounted) {
      return;
    }

    final controller = _controllerForTarget(target);
    controller.text = resolvedSuggestion.displayText;
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    _setLatLngForTarget(
      target,
      resolvedSuggestion.location,
      controller.text.trim(),
    );
    _placesService.resetSession();
    _searchDebounce?.cancel();

    setState(() {
      _isSearchingPlaces = false;
      _hasPlaceSearch = false;
      _placeSuggestions = const [];
    });

    if (target == _RouteSearchTarget.pickup &&
        _destinationController.text.trim().isEmpty) {
      _destinationFocusNode.requestFocus();
    } else if (target == _RouteSearchTarget.stop) {
      _destinationFocusNode.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _addStop() {
    if (_showStopField) {
      setState(() {
        _showStopField = false;
      });
      _stopFocusNode.unfocus();
      return;
    }

    setState(() {
      _showStopField = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _stopFocusNode.requestFocus();
      }
    });
  }

  void _switchRoute() {
    final oldLocation = _locationController.text;
    final oldDestination = _destinationController.text;
    final oldPickupLatLng = _pickupLatLng;
    final oldDestinationLatLng = _destinationLatLng;
    final oldPickupLatLngText = _pickupLatLngText;
    final oldDestinationLatLngText = _destinationLatLngText;

    _locationController.text = oldDestination;
    _destinationController.text = oldLocation;
    _pickupLatLng = oldDestinationLatLng;
    _destinationLatLng = oldPickupLatLng;
    _pickupLatLngText = oldDestinationLatLngText;
    _destinationLatLngText = oldPickupLatLngText;
    _locationController.selection = TextSelection.collapsed(
      offset: _locationController.text.length,
    );
    _destinationController.selection = TextSelection.collapsed(
      offset: _destinationController.text.length,
    );
    _destinationFocusNode.requestFocus();
  }

  void _handleLocationSubmitted(String value) {
    if (value.trim().isNotEmpty) {
      _destinationFocusNode.requestFocus();
    }
  }

  void _handlePrimaryAction() {
    unawaited(_submitRoute());
  }

  Future<void> _submitRoute() async {
    if (!_canRequestRide) {
      return;
    }

    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();

    setState(() {
      _isResolvingRoute = true;
      _isSearchingPlaces = false;
      _hasPlaceSearch = false;
      _placeSuggestions = const [];
    });

    final pickupLatLng = await _resolveLatLngForTarget(
      _RouteSearchTarget.pickup,
    );
    final destinationLatLng = await _resolveLatLngForTarget(
      _RouteSearchTarget.destination,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isResolvingRoute = false;
    });

    if (pickupLatLng == null || destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select valid pickup and destination locations.',
          ),
        ),
      );
      return;
    }

    if (widget.isEditingDestinations) {
      final returnPath = switch (widget.returnTo) {
        'arriving' => '/arriving',
        'ride-arrival' => '/ride-arrival',
        'driving-to-destination' => '/driving-to-destination',
        _ => '/driver-found',
      };
      final routeUri = Uri(
        path: returnPath,
        queryParameters: _routeQueryParameters(
          pickupLatLng: pickupLatLng,
          destinationLatLng: destinationLatLng,
          destinationChanged: returnPath == '/driver-found',
        ),
      );
      context.go(routeUri.toString());
      return;
    }

    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: _routeQueryParameters(
        pickupLatLng: pickupLatLng,
        destinationLatLng: destinationLatLng,
      ),
    );
    context.push(selectRideUri.toString());
  }

  Map<String, String> _routeQueryParameters({
    required LatLng pickupLatLng,
    required LatLng destinationLatLng,
    bool destinationChanged = false,
  }) {
    return {
      'ride': widget.returnRideType,
      'payment': widget.returnPayment,
      'pickup': _locationController.text.trim(),
      'destination': _destinationController.text.trim(),
      ...latLngToQuery('pickup', pickupLatLng),
      ...latLngToQuery('destination', destinationLatLng),
      if (destinationChanged) 'destinationChanged': 'true',
    };
  }

  Future<LatLng?> _resolveLatLngForTarget(_RouteSearchTarget target) async {
    final controller = _controllerForTarget(target);
    final query = controller.text.trim();
    if (query.isEmpty) {
      return null;
    }

    final cachedLatLng = _latLngForTarget(target);
    final cachedText = _latLngTextForTarget(target);
    if (cachedLatLng != null && cachedText == query) {
      return cachedLatLng;
    }

    if (target == _RouteSearchTarget.pickup &&
        (query == 'Current Location' ||
            query == 'My location' ||
            query == 'Set location' ||
            query == 'Locating...')) {
      final fallbackLocation = _locationBias ?? GoogleMapsConfig.defaultCenter;
      _setLatLngForTarget(target, fallbackLocation, query);
      return fallbackLocation;
    }

    final defaultMatch = _defaultPlaceMatch(query);
    if (defaultMatch?.location != null) {
      _setLatLngForTarget(target, defaultMatch!.location, query);
      return defaultMatch.location;
    }

    final suggestions = await _placesService.autocomplete(
      query,
      locationBias: _locationBias,
    );
    if (suggestions.isEmpty) {
      return null;
    }

    final normalizedQuery = query.toLowerCase();
    final suggestion = suggestions.firstWhere(
      (place) =>
          place.displayText.toLowerCase() == normalizedQuery ||
          place.title.toLowerCase() == normalizedQuery,
      orElse: () => suggestions.first,
    );
    final resolved = await _placesService.resolve(suggestion);
    final location = resolved.location;
    if (location != null) {
      _setLatLngForTarget(target, location, query);
    }
    return location;
  }

  CitiridePlace? _defaultPlaceMatch(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return null;
    }

    for (final place in _placesService.defaultPlaces()) {
      if (place.title.toLowerCase() == normalizedQuery ||
          place.displayText.toLowerCase() == normalizedQuery) {
        return place;
      }
    }

    return null;
  }

  LatLng? _latLngForTarget(_RouteSearchTarget target) {
    return switch (target) {
      _RouteSearchTarget.pickup => _pickupLatLng,
      _RouteSearchTarget.stop => _stopLatLng,
      _RouteSearchTarget.destination => _destinationLatLng,
    };
  }

  String? _latLngTextForTarget(_RouteSearchTarget target) {
    return switch (target) {
      _RouteSearchTarget.pickup => _pickupLatLngText,
      _RouteSearchTarget.stop => _stopLatLngText,
      _RouteSearchTarget.destination => _destinationLatLngText,
    };
  }

  void _setLatLngForTarget(
    _RouteSearchTarget target,
    LatLng? location,
    String text,
  ) {
    switch (target) {
      case _RouteSearchTarget.pickup:
        _pickupLatLng = location;
        _pickupLatLngText = location == null ? null : text;
        break;
      case _RouteSearchTarget.stop:
        _stopLatLng = location;
        _stopLatLngText = location == null ? null : text;
        break;
      case _RouteSearchTarget.destination:
        _destinationLatLng = location;
        _destinationLatLngText = location == null ? null : text;
        break;
    }
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
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.citirideBlack,
        body: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 44,
              child: _RouteMapStrip(),
            ),
            Positioned.fill(
              top: 44,
              child: Container(color: AppColors.citirideBlack),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.min(constraints.maxWidth, 430.0);
                final topGap = math.max(
                  MediaQuery.paddingOf(context).top + 14,
                  58.0,
                );

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        topGap,
                        12,
                        MediaQuery.paddingOf(context).bottom + 164,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RouteHeader(onClose: _close),
                          const SizedBox(height: 25),
                          _RouteInputArea(
                            showStopField: _showStopField,
                            locationController: _locationController,
                            stopController: _stopController,
                            destinationController: _destinationController,
                            locationFocusNode: _locationFocusNode,
                            stopFocusNode: _stopFocusNode,
                            destinationFocusNode: _destinationFocusNode,
                            onAddStop: _addStop,
                            onSwitchRoute: _switchRoute,
                            onLocationSubmitted: _handleLocationSubmitted,
                          ),
                          const SizedBox(height: 26),
                          _RouteLocationContent(
                            isSearching: _isSearchingPlaces,
                            hasSearch: _hasPlaceSearch,
                            query: _activeSearchQuery,
                            suggestions: _placeSuggestions,
                            defaultSuggestions: _placesService.defaultPlaces(),
                            onSuggestionSelected: _selectPlaceSuggestion,
                            onDefaultSelected: _selectDefaultPlaceSuggestion,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 64),
                child: _RequestRideButton(
                  isEnabled: _canRequestRide,
                  label: widget.isEditingDestinations
                      ? 'Continue'
                      : 'Request a ride',
                  onPressed: _handlePrimaryAction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteMapStrip extends StatelessWidget {
  const _RouteMapStrip();

  @override
  Widget build(BuildContext context) {
    final fallback = Stack(
      fit: StackFit.expand,
      children: [
        const CompatibleSvgPicture.asset(
          'assets/images/Basemap image.svg',
          fit: BoxFit.cover,
          semanticsLabel: 'Route map background',
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
          ),
        ),
      ],
    );

    return CitirideGoogleMap(
      fallback: fallback,
      fallbackSemanticsLabel: 'Route map background',
    );
  }
}

class _RouteHeader extends StatelessWidget {
  const _RouteHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                onPressed: onClose,
                padding: EdgeInsets.zero,
                splashRadius: 22,
                icon: const Icon(Icons.close, color: AppColors.white, size: 24),
              ),
            ),
          ),
          const Text(
            'Your Route',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteInputArea extends StatelessWidget {
  const _RouteInputArea({
    required this.showStopField,
    required this.locationController,
    required this.stopController,
    required this.destinationController,
    required this.locationFocusNode,
    required this.stopFocusNode,
    required this.destinationFocusNode,
    required this.onAddStop,
    required this.onSwitchRoute,
    required this.onLocationSubmitted,
  });

  final bool showStopField;
  final TextEditingController locationController;
  final TextEditingController stopController;
  final TextEditingController destinationController;
  final FocusNode locationFocusNode;
  final FocusNode stopFocusNode;
  final FocusNode destinationFocusNode;
  final VoidCallback onAddStop;
  final VoidCallback onSwitchRoute;
  final ValueChanged<String> onLocationSubmitted;

  @override
  Widget build(BuildContext context) {
    final cardHeight = showStopField ? 144.0 : 96.0;
    const switchTop = 24.0;
    // Keep Add Stop below the fields card so it doesn't crowd the location row.
    const addStopTopGap = 10.0;
    final totalHeight = cardHeight + addStopTopGap + 36.0;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 48,
            height: cardHeight,
            child: _RouteFieldsCard(
              showStopField: showStopField,
              locationController: locationController,
              stopController: stopController,
              destinationController: destinationController,
              locationFocusNode: locationFocusNode,
              stopFocusNode: stopFocusNode,
              destinationFocusNode: destinationFocusNode,
              onLocationSubmitted: onLocationSubmitted,
            ),
          ),
          Positioned(
            right: 0,
            top: switchTop,
            child: _RouteActionIconButton(
              asset: 'assets/images/switch route_icon.svg',
              semanticsLabel: 'Switch route',
              onTap: onSwitchRoute,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: cardHeight + addStopTopGap,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AddStopTextButton(
                isStopVisible: showStopField,
                onTap: onAddStop,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFieldsCard extends StatelessWidget {
  const _RouteFieldsCard({
    required this.showStopField,
    required this.locationController,
    required this.stopController,
    required this.destinationController,
    required this.locationFocusNode,
    required this.stopFocusNode,
    required this.destinationFocusNode,
    required this.onLocationSubmitted,
  });

  final bool showStopField;
  final TextEditingController locationController;
  final TextEditingController stopController;
  final TextEditingController destinationController;
  final FocusNode locationFocusNode;
  final FocusNode stopFocusNode;
  final FocusNode destinationFocusNode;
  final ValueChanged<String> onLocationSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: _RouteTextFieldRow(
              controller: locationController,
              focusNode: locationFocusNode,
              keyValue: 'route-location-field',
              leading: _RoutePointIndicator(
                isActive: locationController.text.trim().isNotEmpty,
              ),
              textColor: AppColors.white,
              hintText: 'Your Location',
              textInputAction: TextInputAction.next,
              onSubmitted: onLocationSubmitted,
            ),
          ),
          if (showStopField)
            SizedBox(
              height: 48,
              child: _RouteTextFieldRow(
                controller: stopController,
                focusNode: stopFocusNode,
                keyValue: 'route-stop-field',
                leading: const _RoutePointIndicator(),
                hintText: 'Add a stop',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) {
                  destinationFocusNode.requestFocus();
                },
              ),
            ),
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.citirideYellow),
            ),
            child: _RouteTextFieldRow(
              controller: destinationController,
              focusNode: destinationFocusNode,
              keyValue: 'route-destination-field',
              leading: const SizedBox(
                width: 22,
                height: 22,
                child: CompatibleSvgPicture.asset(
                  'assets/images/Search Icon.svg',
                  fit: BoxFit.contain,
                  semanticsLabel: 'Destination search icon',
                ),
              ),
              hintText: 'Your Destination',
              textInputAction: TextInputAction.done,
              trailing: const SizedBox(
                width: 32,
                height: 32,
                child: CompatibleSvgPicture.asset(
                  'assets/images/map icon.svg',
                  fit: BoxFit.contain,
                  semanticsLabel: 'Open map',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTextFieldRow extends StatelessWidget {
  const _RouteTextFieldRow({
    required this.controller,
    required this.focusNode,
    required this.keyValue,
    required this.leading,
    required this.hintText,
    required this.textInputAction,
    this.textColor = const Color(0xFF9B9B9B),
    this.trailing,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String keyValue;
  final Widget leading;
  final String hintText;
  final TextInputAction textInputAction;
  final Color textColor;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 14),
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: ValueKey(keyValue),
            controller: controller,
            focusNode: focusNode,
            cursorColor: AppColors.citirideYellow,
            keyboardAppearance: Brightness.dark,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              fillColor: Colors.transparent,
              hoverColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFF8F8F8F),
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.2,
                letterSpacing: 0,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
          const SizedBox(width: 6),
        ] else
          const SizedBox(width: 14),
      ],
    );
  }
}

class _RoutePointIndicator extends StatelessWidget {
  const _RoutePointIndicator({this.isActive = false});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        color: isActive ? AppColors.citirideYellow : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.citirideYellow : const Color(0xFFC8C8D0),
          width: 2,
        ),
      ),
    );
  }
}

class _RouteActionIconButton extends StatelessWidget {
  const _RouteActionIconButton({
    required this.asset,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String asset;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: CompatibleSvgPicture.asset(
          asset,
          fit: BoxFit.contain,
          semanticsLabel: semanticsLabel,
        ),
      ),
    );
  }
}

class _AddStopTextButton extends StatelessWidget {
  const _AddStopTextButton({
    required this.isStopVisible,
    required this.onTap,
  });

  final bool isStopVisible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = isStopVisible ? 'Remove stop' : 'Add stop';

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isStopVisible ? Icons.remove : Icons.add,
                size: 18,
                color: AppColors.citirideYellow,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.citirideYellow,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteLocationContent extends StatelessWidget {
  const _RouteLocationContent({
    required this.isSearching,
    required this.hasSearch,
    required this.query,
    required this.suggestions,
    required this.defaultSuggestions,
    required this.onSuggestionSelected,
    required this.onDefaultSelected,
  });

  final bool isSearching;
  final bool hasSearch;
  final String query;
  final List<CitiridePlace> suggestions;
  final List<CitiridePlace> defaultSuggestions;
  final ValueChanged<CitiridePlace> onSuggestionSelected;
  final ValueChanged<CitiridePlace> onDefaultSelected;

  @override
  Widget build(BuildContext context) {
    if (hasSearch) {
      final visibleSuggestions = suggestions
          .where((suggestion) => !_isExactMatch(suggestion, query))
          .toList(growable: false);

      if (isSearching) {
        return const SizedBox(height: 238, child: _RouteSearchLoading());
      }

      if (suggestions.isEmpty) {
        return SizedBox(
          height: 274,
          child: LocationSearchEmptyState(query: query),
        );
      }

      if (visibleSuggestions.isEmpty) {
        return const SizedBox(height: 238);
      }

      return Column(
        key: ValueKey('route-place-results-$query'),
        children: [
          for (var index = 0; index < visibleSuggestions.length; index++) ...[
            _LocationListItem(
              iconAsset: 'assets/images/Location_Icon.svg',
              title: visibleSuggestions[index].title,
              subtitle: visibleSuggestions[index].subtitle ?? 'Nigeria',
              distance: '',
              onTap: () => onSuggestionSelected(visibleSuggestions[index]),
            ),
            if (index != visibleSuggestions.length - 1)
              const SizedBox(height: 16),
          ],
        ],
      );
    }

    final saved = defaultSuggestions.skip(1).take(3).toList(growable: false);
    final recent = defaultSuggestions.length > 2
        ? defaultSuggestions[2]
        : defaultSuggestions.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Saved Locations',
          style: TextStyle(
            color: Color(0xFF2C2D36),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < saved.length; index++) ...[
          _LocationListItem(
            iconAsset: index == 0
                ? 'assets/images/Time_Icon.svg'
                : 'assets/images/Location_Icon.svg',
            title: saved[index].title,
            subtitle: saved[index].subtitle ?? 'Nigeria',
            distance: switch (index) {
              0 => '12.6km',
              1 => '<1km',
              _ => '7.2km',
            },
            onTap: () => onDefaultSelected(saved[index]),
          ),
          if (index != saved.length - 1) const SizedBox(height: 16),
        ],
        const SizedBox(height: 34),
        const Text(
          'Recent locations',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 20),
        _LocationListItem(
          iconAsset: 'assets/images/Location_Icon.svg',
          title: recent.title,
          subtitle: recent.subtitle ?? 'Nigeria',
          distance: '<1km',
          onTap: () => onDefaultSelected(recent),
        ),
      ],
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

class _RouteSearchLoading extends StatelessWidget {
  const _RouteSearchLoading();

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

class _LocationListItem extends StatelessWidget {
  const _LocationListItem({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.distance,
    this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final String distance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CompatibleSvgPicture.asset(iconAsset, fit: BoxFit.contain),
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
              const SizedBox(height: 3),
              Text(
                subtitle,
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
          ),
        ),
        if (distance.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            distance,
            style: const TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 9,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _RequestRideButton extends StatelessWidget {
  const _RequestRideButton({
    required this.isEnabled,
    required this.label,
    required this.onPressed,
  });

  final bool isEnabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isEnabled ? onPressed : null,
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color(0xFF3A3A3A);
          }
          return AppColors.citirideYellow;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color(0xFF8F8F8F);
          }
          return AppColors.citirideBlack;
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
      child: Text(label),
    );
  }
}
