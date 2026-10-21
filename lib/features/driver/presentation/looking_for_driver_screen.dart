import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/location/citiride_fare.dart';
import '../../../core/location/citiride_place.dart';
import '../../../core/location/citiride_route.dart';
import '../../../core/location/citiride_route_service.dart';
import '../../../core/location/route_query.dart';
import '../../../core/maps/google_maps_config.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../pickup/presentation/select_pickup_location_screen.dart';
import '../../profile/domain/rider_profile_store.dart';
import '../../ride/data/ride_repository.dart';
import '../../ride/domain/live_ride.dart';
import '../../ride/presentation/ride_trip_session.dart';
import '../../../shared/widgets/citiride_live_route_map.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

const _driverFoundDelay = Duration(seconds: 10);
const _driverConfirmDelay = Duration(seconds: 10);
const _arrivingToRideArrivalDelay = Duration(seconds: 15);
const _rideArrivalToDrivingDelay = Duration(seconds: 15);
const _drivingToRideSuccessDelay = Duration(seconds: 10);

typedef ShareRideLauncher = Future<void> Function(ShareParams params);

@visibleForTesting
ShareRideLauncher? debugShareRideLauncher;
Map<String, String> _rideFlowQueryParameters({
  required String rideType,
  required String paymentMethod,
  required String pickup,
  required String destination,
  LatLng? pickupLatLng,
  LatLng? destinationLatLng,
  String? mode,
  String? returnTo,
  String? rideId,
  double? estimatedFare,
  bool showStop = false,
  bool destinationChanged = false,
}) {
  return {
    'ride': rideType,
    'payment': paymentMethod,
    'pickup': pickup,
    'destination': destination,
    ...latLngToQuery('pickup', pickupLatLng),
    ...latLngToQuery('destination', destinationLatLng),
    ..._optionalQueryParameter('mode', mode),
    ..._optionalQueryParameter('returnTo', returnTo),
    ..._optionalQueryParameter('rideId', rideId),
    if (estimatedFare != null) 'fare': estimatedFare.round().toString(),
    if (showStop) 'showStop': 'true',
    if (destinationChanged) 'destinationChanged': 'true',
  };
}

Map<String, String> _optionalQueryParameter(String key, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return const {};
  }

  return {key: trimmed};
}

String _normalizePickupLabel(String value) {
  final pickup = value.trim();
  return pickup.isEmpty ? 'Current Location' : pickup;
}

String _normalizeDestinationLabel(String value) {
  final destination = value.trim();
  return destination.isEmpty ? 'Ring Road Bus Terminal' : destination;
}

class LookingForDriverScreen extends StatefulWidget {
  const LookingForDriverScreen({
    super.key,
    this.rideType = 'regular',
    this.initialPickupLocation = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.paymentMethod = 'cash',
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.initialEstimatedFare,
    this.existingRideId,
  });

  final String rideType;
  final String initialPickupLocation;
  final String initialDestination;
  final String paymentMethod;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final double? initialEstimatedFare;
  final String? existingRideId;

  @override
  State<LookingForDriverScreen> createState() => _LookingForDriverScreenState();
}

class _LookingForDriverScreenState extends State<LookingForDriverScreen> {
  late String _pickupLocation;
  late String _destination;
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  Timer? _driverFoundTimer;
  final _rideRepository = RideRepository();
  final _routeService = CitirideRouteService();
  final _sessionStore = const CitirideSessionStore();
  StreamSubscription<LiveRide>? _rideSubscription;
  StreamSubscription<List<NearbyDriver>>? _nearbyDriversSub;
  List<NearbyDriver> _nearbyDrivers = const [];
  String? _rideId;
  String? _matchError;
  String? _statusHint;
  bool _isCreatingRequest = true;
  bool _hasNavigatedToDriver = false;
  double? _estimatedFare;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    _destination = _normalizedDestination(widget.initialDestination);
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _estimatedFare = widget.initialEstimatedFare;
    if (_isRunningWidgetTest) {
      _isCreatingRequest = false;
      _driverFoundTimer = Timer(_driverFoundDelay, _showDriverFound);
      return;
    }
    _startNearbyDriversWatch();
    unawaited(_startRideMatching());
  }

  @override
  void didUpdateWidget(covariant LookingForDriverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickupLocation != oldWidget.initialPickupLocation) {
      _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    }
    if (widget.initialDestination != oldWidget.initialDestination) {
      _destination = _normalizedDestination(widget.initialDestination);
    }
    if (widget.initialPickupLatLng != oldWidget.initialPickupLatLng) {
      _pickupLatLng = widget.initialPickupLatLng;
      if (!_isRunningWidgetTest) {
        _startNearbyDriversWatch();
      }
    }
    if (widget.initialDestinationLatLng != oldWidget.initialDestinationLatLng) {
      _destinationLatLng = widget.initialDestinationLatLng;
    }
  }

  @override
  void dispose() {
    _driverFoundTimer?.cancel();
    unawaited(_rideSubscription?.cancel() ?? Future<void>.value());
    unawaited(_nearbyDriversSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _startNearbyDriversWatch() {
    final pickup = _pickupLatLng;
    unawaited(_nearbyDriversSub?.cancel() ?? Future<void>.value());
    _nearbyDriversSub = null;
    if (pickup == null) {
      setState(() {
        _nearbyDrivers = const [];
      });
      return;
    }

    _nearbyDriversSub = _rideRepository.watchNearbyDrivers(center: pickup).listen(
      (drivers) {
        if (!mounted) return;
        setState(() {
          _nearbyDrivers = drivers;
        });
      },
      onError: (_) {
        // Nearby cars are cosmetic; failures should not disrupt the flow.
      },
    );
  }

  String _normalizedPickup(String value) {
    return _normalizePickupLabel(value);
  }

  String _normalizedDestination(String value) {
    return _normalizeDestinationLabel(value);
  }

  Future<void> _startRideMatching() async {
    try {
      final existingRideId = widget.existingRideId?.trim();
      if (existingRideId != null && existingRideId.isNotEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _rideId = existingRideId;
          _isCreatingRequest = false;
          _matchError = null;
        });
        await _rideSubscription?.cancel();
        _rideSubscription = _rideRepository.watchRide(existingRideId).listen(
          _handleRideUpdate,
          onError: (Object error) {
            debugPrint('Ride watch failed: $error');
            if (!mounted) {
              return;
            }
            setState(() {
              _matchError = 'Lost connection to your ride request.';
            });
          },
        );
        return;
      }

      final email = await _sessionStore.signedInEmail();
      if (!mounted) {
        return;
      }

      if (email == null || email.isEmpty) {
        setState(() {
          _isCreatingRequest = false;
          _matchError = 'Sign in to request a ride.';
        });
        return;
      }

      final riderId =
          CitirideAuthService().riderIdForEmail(email) ??
          riderIdFromEmail(email);

      final pickupPoint = _pickupLatLng ?? GoogleMapsConfig.defaultCenter;
      final destinationPoint =
          _destinationLatLng ?? GoogleMapsConfig.defaultCenter;

      final route = await _routeService.routeBetween(
        origin: pickupPoint,
        destination: destinationPoint,
      );
      final estimatedFare = estimatedFareForRideType(
        widget.rideType,
        route: route,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _estimatedFare = estimatedFare;
      });

      final riderProfile = RiderProfileStore.instance.profile.value;
      final ride = await _rideRepository.requestRide(
        NewRideRequest(
          riderId: riderId,
          pickup: RideLatLng(
            lat: pickupPoint.latitude,
            lng: pickupPoint.longitude,
            address: _pickupLocation,
          ),
          destination: RideLatLng(
            lat: destinationPoint.latitude,
            lng: destinationPoint.longitude,
            address: _destination,
          ),
          estimatedFare: estimatedFare,
          rideType: widget.rideType,
          paymentMethod: widget.paymentMethod,
          riderName: riderProfile.displayName,
        ),
      );

      if (!mounted) {
        return;
      }

        setState(() {
          _rideId = ride.id;
          _isCreatingRequest = false;
          _matchError = null;
          _statusHint = null;
        });

      await _rideSubscription?.cancel();
      _rideSubscription = _rideRepository.watchRide(ride.id).listen(
        _handleRideUpdate,
        onError: (Object error) {
          debugPrint('Ride watch failed: $error');
          if (!mounted) {
            return;
          }
          setState(() {
            _matchError = 'Lost connection to your ride request.';
          });
        },
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCreatingRequest = false;
        _matchError = 'Could not reach matching. Retrying...';
      });
      debugPrint('Ride matching failed: $error');
      _driverFoundTimer?.cancel();
      _driverFoundTimer = Timer(_driverFoundDelay, () {
        if (!mounted || _hasNavigatedToDriver || (_rideId?.isNotEmpty ?? false)) {
          return;
        }
        setState(() {
          _isCreatingRequest = true;
          _matchError = null;
        });
        unawaited(_startRideMatching());
      });
    }
  }

  void _handleRideUpdate(LiveRide ride) {
    if (!mounted || _hasNavigatedToDriver) {
      return;
    }

    if (ride.status == RideStatus.cancelled) {
      setState(() {
        _matchError = 'This ride request was cancelled.';
      });
      return;
    }

    if (ride.status.hasDriverAssigned) {
      if (ride.fare.estimated > 0) {
        _estimatedFare = ride.fare.estimated;
      }
      _showDriverFound();
      return;
    }

    if (ride.lastDeclinedAt != null) {
      setState(() {
        _matchError = null;
        _statusHint = 'A driver declined. Looking for another nearby...';
      });
    }
  }

  void _showDriverFound() {
    if (!mounted || _hasNavigatedToDriver) {
      return;
    }
    _hasNavigatedToDriver = true;
    _driverFoundTimer?.cancel();
    unawaited(_rideSubscription?.cancel() ?? Future<void>.value());

    final driverFoundUri = Uri(
      path: '/driver-found',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        rideId: _rideId,
        estimatedFare: _estimatedFare,
      ),
    );
    context.go(driverFoundUri.toString());
  }

  void _close(BuildContext context) {
    _driverFoundTimer?.cancel();
    unawaited(_cancelOpenRequest());
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _editRoute(BuildContext context, {bool showStop = false}) {
    _driverFoundTimer?.cancel();
    unawaited(_cancelOpenRequest());
    final routeUri = Uri(
      path: '/route',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        rideId: _rideId,
        estimatedFare: _estimatedFare,
        showStop: showStop,
      ),
    );
    context.push(routeUri.toString());
  }

  Future<void> _editPickup(BuildContext context) async {
    final selectedLocation = await showModalBottomSheet<CitiridePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) {
        return PickupSearchSheet(initialLocation: _pickupLocation);
      },
    );

    if (selectedLocation == null || !mounted) {
      return;
    }

    setState(() {
      _pickupLocation = selectedLocation.displayText;
      _pickupLatLng = selectedLocation.location ?? _pickupLatLng;
    });
    _startNearbyDriversWatch();
  }

  Future<void> _cancelOpenRequest() async {
    final rideId = _rideId;
    await _rideSubscription?.cancel();
    _rideSubscription = null;
    if (rideId == null || rideId.isEmpty) {
      return;
    }
    try {
      await _rideRepository.cancelRide(rideId);
    } on Object {
      // Best-effort cancel; UI should still leave the matching screen.
    }
  }

  Future<void> _cancelRide(BuildContext context) async {
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (context) {
        return const _CancelRideSheet();
      },
    );

    if (shouldCancel != true || !context.mounted) {
      return;
    }

    _driverFoundTimer?.cancel();
    await _cancelOpenRequest();
    if (!context.mounted) {
      return;
    }

    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
      ),
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
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.citirideBlack,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = math.min(
              224.0,
              math.max(210.0, constraints.maxHeight * 0.265),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _DriverFlowMap(
                    pickupLatLng: _pickupLatLng,
                    destinationLatLng: _destinationLatLng,
                    routeSemanticsLabel: 'Looking route direction',
                    showNearbyCars: true,
                    nearbyDrivers: _nearbyDrivers,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _LookingTopControls(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    onClose: () => _close(context),
                    onEditRoute: () => _editRoute(context),
                    onAddStop: () => _editRoute(context, showStop: true),
                  ),
                ),
                Positioned(
                  right: 27,
                  bottom: panelHeight + 20,
                  child: const _LookingMyLocationButton(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _LookingForDriverPanel(
                    statusMessage: _isCreatingRequest
                        ? 'Sending your ride request...'
                        : (_matchError ??
                              _statusHint ??
                              (_rideId == null
                                  ? 'Looking for a driver nearby'
                                  : 'Waiting for a nearby driver to accept')),
                    onEditPickup: () => _editPickup(context),
                    onCancelRide: () => _cancelRide(context),
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

class DriverFoundScreen extends StatefulWidget {
  const DriverFoundScreen({
    super.key,
    this.rideType = 'regular',
    this.initialPickupLocation = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.paymentMethod = 'cash',
    this.showDestinationChangeNotice = false,
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.estimatedFare,
    this.rideId,
  });

  final String rideType;
  final String initialPickupLocation;
  final String initialDestination;
  final String paymentMethod;
  final bool showDestinationChangeNotice;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final double? estimatedFare;
  final String? rideId;

  @override
  State<DriverFoundScreen> createState() => _DriverFoundScreenState();
}

class _DriverFoundScreenState extends State<DriverFoundScreen> {
  late String _pickupLocation;
  late String _destination;
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  late bool _showDestinationChangeNotice;
  Timer? _arrivingTimer;
  bool _isCardExpanded = false;
  RideTripSession? _tripSession;
  StreamSubscription<RideTripSnapshot>? _tripSub;
  LatLng? _driverLatLng;
  double? _driverHeading;
  String _driverName = 'Driver';
  String? _driverImage;
  String? _driverVehicle;
  String? _driverPlate;
  bool _hasNavigated = false;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  Map<String, String> get _flowQuery {
    return _rideFlowQueryParameters(
      rideType: widget.rideType,
      paymentMethod: widget.paymentMethod,
      pickup: _pickupLocation,
      destination: _destination,
      pickupLatLng: _pickupLatLng,
      destinationLatLng: _destinationLatLng,
      rideId: widget.rideId ?? _tripSession?.rideId,
      estimatedFare: widget.estimatedFare,
    );
  }

  String get _fareLabel {
    final amount =
        widget.estimatedFare ?? estimatedFareForRideType(widget.rideType);
    return formatNaira(amount);
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    _destination = _normalizedDestination(widget.initialDestination);
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _showDestinationChangeNotice = widget.showDestinationChangeNotice;
    _isCardExpanded = widget.showDestinationChangeNotice;
    _bindTripOrDemoTimer();
  }

  void _bindTripOrDemoTimer() {
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty || _isRunningWidgetTest) {
      _startArrivingTimer();
      return;
    }

    _tripSession = RideTripSession(rideId: rideId)..start();
    _tripSub = _tripSession!.snapshots.listen((snapshot) {
      if (!mounted || _hasNavigated) {
        return;
      }
      setState(() {
        _driverLatLng = snapshot.driverLatLng;
        _driverHeading = snapshot.driverHeading;
        _driverName = snapshot.driverName;
        _driverImage = snapshot.driverImage;
        _driverVehicle = snapshot.driverVehicle;
        _driverPlate = snapshot.driverPlate;
      });
      navigateForRideSnapshot(
        context: context,
        screenStatus: RideStatus.accepted,
        snapshot: snapshot,
        queryParameters: _flowQuery,
      );
      if (shouldNavigateForStatus(
        currentScreen: RideStatus.accepted,
        fromFirestore: snapshot.ride.status,
      )) {
        _hasNavigated = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant DriverFoundScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickupLocation != oldWidget.initialPickupLocation) {
      _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    }
    if (widget.initialDestination != oldWidget.initialDestination) {
      _destination = _normalizedDestination(widget.initialDestination);
    }
    if (widget.initialPickupLatLng != oldWidget.initialPickupLatLng) {
      _pickupLatLng = widget.initialPickupLatLng;
    }
    if (widget.initialDestinationLatLng != oldWidget.initialDestinationLatLng) {
      _destinationLatLng = widget.initialDestinationLatLng;
    }
    if (widget.showDestinationChangeNotice !=
        oldWidget.showDestinationChangeNotice) {
      _showDestinationChangeNotice = widget.showDestinationChangeNotice;
      if (_showDestinationChangeNotice) {
        _isCardExpanded = true;
      }
    }
    if (widget.rideId != oldWidget.rideId) {
      unawaited(_disposeTrip());
      _bindTripOrDemoTimer();
    } else if ((widget.rideId == null || widget.rideId!.isEmpty) &&
        (widget.initialPickupLocation != oldWidget.initialPickupLocation ||
            widget.initialDestination != oldWidget.initialDestination ||
            widget.showDestinationChangeNotice !=
                oldWidget.showDestinationChangeNotice)) {
      _startArrivingTimer();
    }
  }

  Future<void> _disposeTrip() async {
    await _tripSub?.cancel();
    _tripSub = null;
    await _tripSession?.dispose();
    _tripSession = null;
  }

  @override
  void dispose() {
    _arrivingTimer?.cancel();
    unawaited(_disposeTrip());
    super.dispose();
  }

  void _startArrivingTimer() {
    if (widget.rideId != null && widget.rideId!.trim().isNotEmpty) {
      return;
    }
    _arrivingTimer?.cancel();
    _arrivingTimer = Timer(_driverConfirmDelay, _showArriving);
  }

  void _showArriving() {
    if (!mounted || _hasNavigated) {
      return;
    }
    _hasNavigated = true;

    final arrivingUri = Uri(
      path: '/arriving',
      queryParameters: _flowQuery,
    );
    context.go(arrivingUri.toString());
  }

  String _normalizedPickup(String value) {
    return _normalizePickupLabel(value);
  }

  String _normalizedDestination(String value) {
    return _normalizeDestinationLabel(value);
  }

  void _expandCard() {
    if (_isCardExpanded) {
      return;
    }

    setState(() {
      _isCardExpanded = true;
    });
  }

  void _collapseCard() {
    if (!_isCardExpanded) {
      return;
    }

    setState(() {
      _isCardExpanded = false;
    });
  }

  void _close(BuildContext context) {
    _arrivingTimer?.cancel();
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _editRoute(BuildContext context, {bool showStop = false}) {
    _arrivingTimer?.cancel();
    final routeUri = Uri(
      path: '/route',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        mode: 'edit-destinations',
        showStop: showStop,
      ),
    );
    context.push(routeUri.toString());
  }

  Future<void> _editPickup(BuildContext context) async {
    final selectedLocation = await showModalBottomSheet<CitiridePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) {
        return PickupSearchSheet(initialLocation: _pickupLocation);
      },
    );

    if (selectedLocation == null || !mounted) {
      return;
    }

    setState(() {
      _pickupLocation = selectedLocation.displayText;
      _pickupLatLng = selectedLocation.location ?? _pickupLatLng;
    });
  }

  Future<void> _cancelRide(BuildContext context) async {
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (context) {
        return const _CancelRideSheet();
      },
    );

    if (shouldCancel != true || !context.mounted) {
      return;
    }

    _arrivingTimer?.cancel();
    final selectRideUri = Uri(
      path: '/select-ride',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
      ),
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
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.citirideBlack,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final collapsedPanelHeight = math.min(
              258.0,
              math.max(242.0, constraints.maxHeight * 0.306),
            );
            final expandedPanelHeight = math.min(
              590.0,
              math.max(560.0, constraints.maxHeight * 0.70),
            );
            final panelHeight = _isCardExpanded
                ? expandedPanelHeight
                : collapsedPanelHeight;

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _DriverFlowMap(
                    pickupLatLng: _pickupLatLng,
                    destinationLatLng: _destinationLatLng,
                    routeSemanticsLabel: 'Driver found map cars',
                    vehicleProgress: _driverLatLng == null ? 0.08 : null,
                    driverLatLng: _driverLatLng,
                    driverHeading: _driverHeading,
                    vehicleAsset: 'assets/images/car.png',
                    vehicleWidth: 44,
                    vehicleHeight: 54,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _LookingTopControls(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    onClose: () => _close(context),
                    onEditRoute: () => _editRoute(context),
                    onAddStop: () => _editRoute(context, showStop: true),
                  ),
                ),
                Positioned(
                  right: 27,
                  bottom: panelHeight + 20,
                  child: const _LookingMyLocationButton(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _DriverFoundPanel(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    showDestinationChangeNotice: _showDestinationChangeNotice,
                    isExpanded: _isCardExpanded,
                    paymentMethod: widget.paymentMethod,
                    fareLabel: _fareLabel,
                    onExpand: _expandCard,
                    onCollapse: _collapseCard,
                    onEditPickup: () => _editPickup(context),
                    onEditRoute: () => _editRoute(context),
                    onNotesTap: () =>
                      _showPickupNotesChat(
                        context,
                        driverName: _driverName,
                        driverImage: _driverImage,
                        driverVehicle: _driverVehicle,
                        driverPlate: _driverPlate,
                      ),
                    onCancelRide: () => _cancelRide(context),
                    driverName: _driverName,
                    driverImage: _driverImage,
                    driverVehicle: _driverVehicle,
                    driverPlate: _driverPlate,
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

enum _ArrivingSheetStage { collapsed, preview, expanded }

class ArrivingScreen extends StatefulWidget {
  const ArrivingScreen({
    super.key,
    this.rideType = 'regular',
    this.initialPickupLocation = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.paymentMethod = 'cash',
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.estimatedFare,
    this.rideId,
  });

  final String rideType;
  final String initialPickupLocation;
  final String initialDestination;
  final String paymentMethod;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final double? estimatedFare;
  final String? rideId;

  @override
  State<ArrivingScreen> createState() => _ArrivingScreenState();
}

class _ArrivingScreenState extends State<ArrivingScreen> {
  late String _pickupLocation;
  late String _destination;
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  _ArrivingSheetStage _sheetStage = _ArrivingSheetStage.collapsed;
  Timer? _rideArrivalTimer;
  RideTripSession? _tripSession;
  StreamSubscription<RideTripSnapshot>? _tripSub;
  LatLng? _driverLatLng;
  double? _driverHeading;
  String _driverName = 'Driver';
  String? _driverImage;
  String? _driverVehicle;
  String? _driverPlate;
  int _etaMinutes = 2;
  bool _hasNavigated = false;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  Map<String, String> get _flowQuery {
    return _rideFlowQueryParameters(
      rideType: widget.rideType,
      paymentMethod: widget.paymentMethod,
      pickup: _pickupLocation,
      destination: _destination,
      pickupLatLng: _pickupLatLng,
      destinationLatLng: _destinationLatLng,
      rideId: widget.rideId ?? _tripSession?.rideId,
      estimatedFare: widget.estimatedFare,
    );
  }

  String get _fareLabel {
    final amount =
        widget.estimatedFare ?? estimatedFareForRideType(widget.rideType);
    return formatNaira(amount);
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    _destination = _normalizedDestination(widget.initialDestination);
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _bindTripOrDemoTimer();
  }

  void _bindTripOrDemoTimer() {
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty || _isRunningWidgetTest) {
      _startRideArrivalTimer();
      return;
    }
    _tripSession = RideTripSession(rideId: rideId)..start();
    _tripSub = _tripSession!.snapshots.listen((snapshot) {
      if (!mounted || _hasNavigated) {
        return;
      }
      setState(() {
        _driverLatLng = snapshot.driverLatLng;
        _driverHeading = snapshot.driverHeading;
        _driverName = snapshot.driverName;
        _driverImage = snapshot.driverImage;
        _driverVehicle = snapshot.driverVehicle;
        _driverPlate = snapshot.driverPlate;
      });
      navigateForRideSnapshot(
        context: context,
        screenStatus: RideStatus.arriving,
        snapshot: snapshot,
        queryParameters: _flowQuery,
      );
      if (shouldNavigateForStatus(
        currentScreen: RideStatus.arriving,
        fromFirestore: snapshot.ride.status,
      )) {
        _hasNavigated = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant ArrivingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickupLocation != oldWidget.initialPickupLocation) {
      _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    }
    if (widget.initialDestination != oldWidget.initialDestination) {
      _destination = _normalizedDestination(widget.initialDestination);
    }
    if (widget.initialPickupLatLng != oldWidget.initialPickupLatLng) {
      _pickupLatLng = widget.initialPickupLatLng;
    }
    if (widget.initialDestinationLatLng != oldWidget.initialDestinationLatLng) {
      _destinationLatLng = widget.initialDestinationLatLng;
    }
    if (widget.rideId != oldWidget.rideId) {
      unawaited(_disposeTrip());
      _bindTripOrDemoTimer();
    } else if ((widget.rideId == null || widget.rideId!.isEmpty) &&
        (widget.initialPickupLocation != oldWidget.initialPickupLocation ||
            widget.initialDestination != oldWidget.initialDestination)) {
      _startRideArrivalTimer();
    }
  }

  Future<void> _disposeTrip() async {
    await _tripSub?.cancel();
    _tripSub = null;
    await _tripSession?.dispose();
    _tripSession = null;
  }

  @override
  void dispose() {
    _rideArrivalTimer?.cancel();
    unawaited(_disposeTrip());
    super.dispose();
  }

  void _startRideArrivalTimer() {
    if (widget.rideId != null && widget.rideId!.trim().isNotEmpty) {
      return;
    }
    _rideArrivalTimer?.cancel();
    _rideArrivalTimer = Timer(_arrivingToRideArrivalDelay, _showRideArrival);
  }

  void _showRideArrival() {
    if (!mounted || _hasNavigated) {
      return;
    }
    _hasNavigated = true;

    final rideArrivalUri = Uri(
      path: '/ride-arrival',
      queryParameters: _flowQuery,
    );
    context.go(rideArrivalUri.toString());
  }

  String _normalizedPickup(String value) {
    return _normalizePickupLabel(value);
  }

  String _normalizedDestination(String value) {
    return _normalizeDestinationLabel(value);
  }

  void _advanceSheet() {
    if (_sheetStage == _ArrivingSheetStage.expanded) {
      return;
    }

    setState(() {
      _sheetStage = _ArrivingSheetStage.values[_sheetStage.index + 1];
    });
  }

  void _retreatSheet() {
    if (_sheetStage == _ArrivingSheetStage.collapsed) {
      return;
    }

    setState(() {
      _sheetStage = _ArrivingSheetStage.values[_sheetStage.index - 1];
    });
  }

  void _close(BuildContext context) {
    _rideArrivalTimer?.cancel();
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _editRoute(BuildContext context, {bool showStop = false}) {
    _rideArrivalTimer?.cancel();
    final routeUri = Uri(
      path: '/route',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        mode: 'edit-destinations',
        returnTo: 'arriving',
        showStop: showStop,
      ),
    );
    context.push(routeUri.toString());
  }

  Future<void> _editPickup(BuildContext context) async {
    _rideArrivalTimer?.cancel();
    final selectedLocation = await showModalBottomSheet<CitiridePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) {
        return PickupSearchSheet(initialLocation: _pickupLocation);
      },
    );

    if (selectedLocation == null || !mounted) {
      if (mounted) {
        _startRideArrivalTimer();
      }
      return;
    }

    setState(() {
      _pickupLocation = selectedLocation.displayText;
      _pickupLatLng = selectedLocation.location ?? _pickupLatLng;
    });
    _startRideArrivalTimer();
  }

  Future<void> _cancelRide(BuildContext context) async {
    _rideArrivalTimer?.cancel();
    final shouldContinueCancellation = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder: (context) {
        return const _ArrivingCancelRideSheet();
      },
    );

    if (shouldContinueCancellation != true || !context.mounted) {
      if (mounted) {
        _startRideArrivalTimer();
      }
      return;
    }

    final reasonUri = Uri(
      path: '/cancel-ride-reason',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
      ),
    );
    context.go(reasonUri.toString());
  }

  Future<void> _shareRide(BuildContext context) async {
    _rideArrivalTimer?.cancel();
    await _showShareRideDetails(
      context,
      pickupLocation: _pickupLocation,
      destination: _destination,
      driverName: _driverName,
      driverVehicle: _driverVehicle,
      driverPlate: _driverPlate,
    );
    if (!mounted) {
      return;
    }

    _startRideArrivalTimer();
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
            final collapsedPanelHeight = math.min(
              380.0,
              math.max(354.0, constraints.maxHeight * 0.43),
            );
            final expandedPanelHeight = math.min(
              constraints.maxHeight - 10,
              math.max(760.0, constraints.maxHeight * 0.985),
            );
            final previewPanelHeight = math.min(
              expandedPanelHeight - 150,
              math.max(
                collapsedPanelHeight + 150,
                constraints.maxHeight * 0.72,
              ),
            );
            final panelHeight = switch (_sheetStage) {
              _ArrivingSheetStage.collapsed => collapsedPanelHeight,
              _ArrivingSheetStage.preview => previewPanelHeight,
              _ArrivingSheetStage.expanded => expandedPanelHeight,
            };
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _DriverFlowMap(
                    pickupLatLng: _pickupLatLng,
                    destinationLatLng: _destinationLatLng,
                    routeSemanticsLabel: 'Arriving map image',
                    vehicleProgress: _driverLatLng == null ? 0.18 : null,
                    driverLatLng: _driverLatLng,
                    driverHeading: _driverHeading,
                    vehicleAsset: 'assets/images/car.png',
                    vehicleWidth: 44,
                    vehicleHeight: 54,
                    routeDriverToPickup: true,
                    onRouteDuration: (duration) {
                      if (!mounted) return;
                      final minutes =
                          duration.inSeconds <= 0
                              ? 1
                              : (duration.inSeconds / 60).ceil().clamp(1, 99);
                      if (minutes != _etaMinutes) {
                        setState(() => _etaMinutes = minutes);
                      }
                    },
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _LookingTopControls(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    onClose: () => _close(context),
                    onEditRoute: () => _editRoute(context),
                    onAddStop: () => _editRoute(context, showStop: true),
                  ),
                ),
                if (_sheetStage == _ArrivingSheetStage.collapsed)
                  Positioned(
                    right: 27,
                    bottom: panelHeight + 28,
                    child: const _LookingMyLocationButton(),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _ArrivingPanel(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    sheetStage: _sheetStage,
                    paymentMethod: widget.paymentMethod,
                    fareLabel: _fareLabel,
                    onAdvance: _advanceSheet,
                    onRetreat: _retreatSheet,
                    onEditPickup: () => _editPickup(context),
                    onEditRoute: () => _editRoute(context),
                    onNotesTap: () =>
                      _showPickupNotesChat(
                        context,
                        driverName: _driverName,
                        driverImage: _driverImage,
                        driverVehicle: _driverVehicle,
                        driverPlate: _driverPlate,
                      ),
                    onShareRide: () => _shareRide(context),
                    onCancelRide: () => _cancelRide(context),
                    driverName: _driverName,
                    driverImage: _driverImage,
                    driverVehicle: _driverVehicle,
                    driverPlate: _driverPlate,
                    etaMinutes: _etaMinutes,
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

class RideArrivalScreen extends StatefulWidget {
  const RideArrivalScreen({
    super.key,
    this.rideType = 'regular',
    this.initialPickupLocation = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.paymentMethod = 'cash',
    this.autoStartTrip = true,
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.estimatedFare,
    this.rideId,
  });

  final String rideType;
  final String initialPickupLocation;
  final String initialDestination;
  final String paymentMethod;
  final bool autoStartTrip;
  final double? estimatedFare;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final String? rideId;

  @override
  State<RideArrivalScreen> createState() => _RideArrivalScreenState();
}

class _RideArrivalScreenState extends State<RideArrivalScreen> {
  late String _pickupLocation;
  late String _destination;
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  Timer? _drivingTimer;
  Timer? _waitingTimer;
  int _remainingWaitSeconds = CitirideFareRates.waitingGraceMinutes * 60;
  int _overtimeWaitSeconds = 0;
  RideTripSession? _tripSession;
  StreamSubscription<RideTripSnapshot>? _tripSub;
  LatLng? _driverLatLng;
  double? _driverHeading;
  String _driverName = 'Driver';
  String? _driverImage;
  String? _driverVehicle;
  String? _driverPlate;
  bool _hasNavigated = false;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  Map<String, String> get _flowQuery {
    return _rideFlowQueryParameters(
      rideType: widget.rideType,
      paymentMethod: widget.paymentMethod,
      pickup: _pickupLocation,
      destination: _destination,
      pickupLatLng: _pickupLatLng,
      destinationLatLng: _destinationLatLng,
      rideId: widget.rideId ?? _tripSession?.rideId,
      estimatedFare: widget.estimatedFare,
    );
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    _destination = _normalizedDestination(widget.initialDestination);
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _startWaitingTimer();
    _bindTripOrDemoTimer();
  }

  void _bindTripOrDemoTimer() {
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty || _isRunningWidgetTest) {
      if (widget.autoStartTrip) {
        _startDrivingTimer();
      }
      return;
    }
    _tripSession = RideTripSession(rideId: rideId)..start();
    _tripSub = _tripSession!.snapshots.listen((snapshot) {
      if (!mounted || _hasNavigated) {
        return;
      }
      setState(() {
        _driverLatLng = snapshot.driverLatLng;
        _driverHeading = snapshot.driverHeading;
        _driverName = snapshot.driverName;
        _driverImage = snapshot.driverImage;
        _driverVehicle = snapshot.driverVehicle;
        _driverPlate = snapshot.driverPlate;
      });
      navigateForRideSnapshot(
        context: context,
        screenStatus: RideStatus.waiting,
        snapshot: snapshot,
        queryParameters: _flowQuery,
      );
      if (shouldNavigateForStatus(
        currentScreen: RideStatus.waiting,
        fromFirestore: snapshot.ride.status,
      )) {
        _hasNavigated = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant RideArrivalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickupLocation != oldWidget.initialPickupLocation) {
      _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    }
    if (widget.initialDestination != oldWidget.initialDestination) {
      _destination = _normalizedDestination(widget.initialDestination);
    }
    if (widget.initialPickupLatLng != oldWidget.initialPickupLatLng) {
      _pickupLatLng = widget.initialPickupLatLng;
    }
    if (widget.initialDestinationLatLng != oldWidget.initialDestinationLatLng) {
      _destinationLatLng = widget.initialDestinationLatLng;
    }
    if (widget.rideId != oldWidget.rideId) {
      unawaited(_disposeTrip());
      _bindTripOrDemoTimer();
    } else if ((widget.rideId == null || widget.rideId!.isEmpty) &&
        widget.autoStartTrip != oldWidget.autoStartTrip &&
        widget.autoStartTrip) {
      _startDrivingTimer();
    }
  }

  Future<void> _disposeTrip() async {
    await _tripSub?.cancel();
    _tripSub = null;
    await _tripSession?.dispose();
    _tripSession = null;
  }

  @override
  void dispose() {
    _drivingTimer?.cancel();
    _waitingTimer?.cancel();
    unawaited(_disposeTrip());
    super.dispose();
  }

  String _normalizedPickup(String value) {
    return _normalizePickupLabel(value);
  }

  String _normalizedDestination(String value) {
    return _normalizeDestinationLabel(value);
  }

  void _startDrivingTimer() {
    if (widget.rideId != null && widget.rideId!.trim().isNotEmpty) {
      return;
    }
    _drivingTimer?.cancel();
    _drivingTimer = Timer(
      _rideArrivalToDrivingDelay,
      _showDrivingToDestination,
    );
  }

  void _startWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_remainingWaitSeconds > 0) {
          _remainingWaitSeconds -= 1;
        } else {
          _overtimeWaitSeconds += 1;
        }
      });
    });
  }

  void _showDrivingToDestination() {
    if (!mounted || _hasNavigated) {
      return;
    }
    _hasNavigated = true;

    final drivingUri = Uri(
      path: '/driving-to-destination',
      queryParameters: _flowQuery,
    );
    context.go(drivingUri.toString());
  }

  void _close(BuildContext context) {
    _drivingTimer?.cancel();
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _editRoute(BuildContext context, {bool showStop = false}) {
    _drivingTimer?.cancel();
    final routeUri = Uri(
      path: '/route',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        mode: 'edit-destinations',
        returnTo: 'ride-arrival',
        showStop: showStop,
      ),
    );
    context.push(routeUri.toString());
  }

  String get _waitTimeLabel {
    final minutes = (_remainingWaitSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingWaitSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _shareRide(BuildContext context) async {
    _drivingTimer?.cancel();
    await _showShareRideDetails(
      context,
      pickupLocation: _pickupLocation,
      destination: _destination,
      driverName: _driverName,
      driverVehicle: _driverVehicle,
      driverPlate: _driverPlate,
    );
    if (!mounted || !widget.autoStartTrip) {
      return;
    }

    _startDrivingTimer();
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
              326.0,
              math.max(306.0, constraints.maxHeight * 0.37),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _DriverFlowMap(
                    pickupLatLng: _pickupLatLng,
                    destinationLatLng: _destinationLatLng,
                    routeSemanticsLabel: 'Ride arrival map image',
                    vehicleProgress: _driverLatLng == null ? 0.02 : null,
                    driverLatLng: _driverLatLng,
                    driverHeading: _driverHeading,
                    vehicleAsset: 'assets/images/car.png',
                    vehicleWidth: 44,
                    vehicleHeight: 54,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _LookingTopControls(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    onClose: () => _close(context),
                    onEditRoute: () => _editRoute(context),
                    onAddStop: () => _editRoute(context, showStop: true),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _RideArrivalPanel(
                    remainingWaitSeconds: _remainingWaitSeconds,
                    overtimeWaitSeconds: _overtimeWaitSeconds,
                    waitTimeLabel: _waitTimeLabel,
                    onNotesTap: () =>
                      _showPickupNotesChat(
                        context,
                        driverName: _driverName,
                        driverImage: _driverImage,
                        driverVehicle: _driverVehicle,
                        driverPlate: _driverPlate,
                      ),
                    onCallTap: () {},
                    onShareTap: () => _shareRide(context),
                    driverName: _driverName,
                    driverImage: _driverImage,
                    driverVehicle: _driverVehicle,
                    driverPlate: _driverPlate,
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

class DrivingToDestinationScreen extends StatefulWidget {
  const DrivingToDestinationScreen({
    super.key,
    this.rideType = 'regular',
    this.initialPickupLocation = 'Current Location',
    this.initialDestination = 'Ring Road Bus Terminal',
    this.paymentMethod = 'cash',
    this.autoCompleteTrip = false,
    this.initialPickupLatLng,
    this.initialDestinationLatLng,
    this.estimatedFare,
    this.rideId,
  });

  final String rideType;
  final String initialPickupLocation;
  final String initialDestination;
  final String paymentMethod;
  final bool autoCompleteTrip;
  final LatLng? initialPickupLatLng;
  final LatLng? initialDestinationLatLng;
  final double? estimatedFare;
  final String? rideId;

  @override
  State<DrivingToDestinationScreen> createState() =>
      _DrivingToDestinationScreenState();
}

class _DrivingToDestinationScreenState
    extends State<DrivingToDestinationScreen> {
  late String _pickupLocation;
  late String _destination;
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  Timer? _rideSuccessTimer;
  RideTripSession? _tripSession;
  StreamSubscription<RideTripSnapshot>? _tripSub;
  LatLng? _driverLatLng;
  double? _driverHeading;
  String _driverName = 'Driver';
  String? _driverImage;
  String? _driverVehicle;
  String? _driverPlate;
  bool _hasNavigated = false;

  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  Map<String, String> get _flowQuery {
    return _rideFlowQueryParameters(
      rideType: widget.rideType,
      paymentMethod: widget.paymentMethod,
      pickup: _pickupLocation,
      destination: _destination,
      pickupLatLng: _pickupLatLng,
      destinationLatLng: _destinationLatLng,
      rideId: widget.rideId ?? _tripSession?.rideId,
      estimatedFare: widget.estimatedFare,
    );
  }

  @override
  void initState() {
    super.initState();
    _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    _destination = _normalizedDestination(widget.initialDestination);
    _pickupLatLng = widget.initialPickupLatLng;
    _destinationLatLng = widget.initialDestinationLatLng;
    _bindTripOrDemoTimer();
  }

  void _bindTripOrDemoTimer() {
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty || _isRunningWidgetTest) {
      if (widget.autoCompleteTrip) {
        _startRideSuccessTimer();
      }
      return;
    }
    _tripSession = RideTripSession(rideId: rideId)..start();
    _tripSub = _tripSession!.snapshots.listen((snapshot) {
      if (!mounted || _hasNavigated) {
        return;
      }
      setState(() {
        _driverLatLng = snapshot.driverLatLng;
        _driverHeading = snapshot.driverHeading;
        _driverName = snapshot.driverName;
        _driverImage = snapshot.driverImage;
        _driverVehicle = snapshot.driverVehicle;
        _driverPlate = snapshot.driverPlate;
      });
      navigateForRideSnapshot(
        context: context,
        screenStatus: RideStatus.inProgress,
        snapshot: snapshot,
        queryParameters: _flowQuery,
      );
      if (shouldNavigateForStatus(
        currentScreen: RideStatus.inProgress,
        fromFirestore: snapshot.ride.status,
      )) {
        _hasNavigated = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant DrivingToDestinationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickupLocation != oldWidget.initialPickupLocation) {
      _pickupLocation = _normalizedPickup(widget.initialPickupLocation);
    }
    if (widget.initialDestination != oldWidget.initialDestination) {
      _destination = _normalizedDestination(widget.initialDestination);
    }
    if (widget.initialPickupLatLng != oldWidget.initialPickupLatLng) {
      _pickupLatLng = widget.initialPickupLatLng;
    }
    if (widget.initialDestinationLatLng != oldWidget.initialDestinationLatLng) {
      _destinationLatLng = widget.initialDestinationLatLng;
    }
    if (widget.rideId != oldWidget.rideId) {
      unawaited(_disposeTrip());
      _bindTripOrDemoTimer();
    } else if ((widget.rideId == null || widget.rideId!.isEmpty) &&
        widget.autoCompleteTrip &&
        (widget.initialPickupLocation != oldWidget.initialPickupLocation ||
            widget.initialDestination != oldWidget.initialDestination ||
            widget.paymentMethod != oldWidget.paymentMethod ||
            widget.rideType != oldWidget.rideType ||
            widget.autoCompleteTrip != oldWidget.autoCompleteTrip)) {
      _startRideSuccessTimer();
    }
  }

  Future<void> _disposeTrip() async {
    await _tripSub?.cancel();
    _tripSub = null;
    await _tripSession?.dispose();
    _tripSession = null;
  }

  @override
  void dispose() {
    _rideSuccessTimer?.cancel();
    unawaited(_disposeTrip());
    super.dispose();
  }

  String _normalizedPickup(String value) {
    return _normalizePickupLabel(value);
  }

  String _normalizedDestination(String value) {
    return _normalizeDestinationLabel(value);
  }

  void _startRideSuccessTimer() {
    if (widget.rideId != null && widget.rideId!.trim().isNotEmpty) {
      return;
    }
    _rideSuccessTimer?.cancel();
    _rideSuccessTimer = Timer(_drivingToRideSuccessDelay, _showRideSuccess);
  }

  void _showRideSuccess() {
    if (!mounted || _hasNavigated) {
      return;
    }
    _hasNavigated = true;

    final rideSuccessUri = Uri(
      path: '/ride-success',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
        if (widget.estimatedFare != null)
          'fare': widget.estimatedFare!.round().toString(),
        if (widget.rideId != null && widget.rideId!.trim().isNotEmpty)
          'rideId': widget.rideId!.trim(),
      },
    );
    context.go(rideSuccessUri.toString());
  }

  void _close(BuildContext context) {
    _rideSuccessTimer?.cancel();
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/home');
  }

  void _editRoute(BuildContext context, {bool showStop = false}) {
    _rideSuccessTimer?.cancel();
    final routeUri = Uri(
      path: '/route',
      queryParameters: _rideFlowQueryParameters(
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        pickup: _pickupLocation,
        destination: _destination,
        pickupLatLng: _pickupLatLng,
        destinationLatLng: _destinationLatLng,
        mode: 'edit-destinations',
        returnTo: 'driving-to-destination',
        showStop: showStop,
      ),
    );
    context.push(routeUri.toString());
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
              276.0,
              math.max(252.0, constraints.maxHeight * 0.31),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _DriverFlowMap(
                    pickupLatLng: _pickupLatLng,
                    destinationLatLng: _destinationLatLng,
                    routeSemanticsLabel: 'Driving to destination map image',
                    vehicleProgress: _driverLatLng == null ? 0.46 : null,
                    driverLatLng: _driverLatLng,
                    driverHeading: _driverHeading,
                    vehicleAsset: 'assets/images/car.png',
                    vehicleWidth: 44,
                    vehicleHeight: 54,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: math.max(MediaQuery.paddingOf(context).top + 12, 50),
                  child: _LookingTopControls(
                    pickupLocation: _pickupLocation,
                    destination: _destination,
                    onClose: () => _close(context),
                    onEditRoute: () => _editRoute(context),
                    onAddStop: () => _editRoute(context, showStop: true),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: _DrivingToDestinationPanel(
                    destination: _destination,
                    onDestinationTap: () => _editRoute(context),
                    driverName: _driverName,
                    driverImage: _driverImage,
                    driverVehicle: _driverVehicle,
                    driverPlate: _driverPlate,
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

class _RideArrivalPanel extends StatelessWidget {
  const _RideArrivalPanel({
    required this.remainingWaitSeconds,
    required this.overtimeWaitSeconds,
    required this.waitTimeLabel,
    required this.onNotesTap,
    required this.onCallTap,
    required this.onShareTap,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final int remainingWaitSeconds;
  final int overtimeWaitSeconds;
  final String waitTimeLabel;
  final VoidCallback onNotesTap;
  final VoidCallback onCallTap;
  final VoidCallback onShareTap;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  bool get _isFeeDue => remainingWaitSeconds <= 0;

  String get _waitingFeeLabel {
    final waited = Duration(
      minutes: CitirideFareRates.waitingGraceMinutes,
      seconds: overtimeWaitSeconds,
    );
    final fare = CitirideFareCalculator.waitingFareFor(waited);
    if (fare <= 0) {
      return 'Waiting fee \u20A6${CitirideFareRates.waitingPerMinute.round()}/min applies';
    }
    return 'Waiting fee ${formatNaira(fare)} applies';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ride-arrival-card'),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DriverSheetHandle(),
          const SizedBox(height: 16),
          const Text(
            'Your ride has arrived',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          _RideArrivalWaitStatus(
            isFeeDue: _isFeeDue,
            waitTimeLabel: waitTimeLabel,
            waitingFeeLabel: _waitingFeeLabel,
          ),
          const SizedBox(height: 16),
          _ArrivingDriverInfo(
            leadingInset: 8,
            driverName: driverName,
            driverImage: driverImage,
            driverVehicle: driverVehicle,
            driverPlate: driverPlate,
          ),
          const SizedBox(height: 20),
          _PickupNotesAndCallRow(onNotesTap: onNotesTap, onCallTap: onCallTap),
          const Spacer(),
          _ArrivingMoreActionRow(
            iconAsset: 'assets/images/share ride icon.svg',
            label: 'Share ride details',
            semanticsLabel: 'Share ride details',
            color: const Color(0xFF8F8F8F),
            onTap: onShareTap,
          ),
        ],
      ),
    );
  }
}

class _RideArrivalWaitStatus extends StatelessWidget {
  const _RideArrivalWaitStatus({
    required this.isFeeDue,
    required this.waitTimeLabel,
    required this.waitingFeeLabel,
  });

  final bool isFeeDue;
  final String waitTimeLabel;
  final String waitingFeeLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: isFeeDue
          ? Text(
              waitingFeeLabel,
              key: const ValueKey('waiting-fee-due'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFF3838),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.2,
                letterSpacing: 0,
              ),
            )
          : Text(
              'Free wait time $waitTimeLabel',
              key: const ValueKey('free-wait-countdown'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.citirideYellow,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
    );
  }
}

class _DrivingToDestinationPanel extends StatelessWidget {
  const _DrivingToDestinationPanel({
    required this.destination,
    required this.onDestinationTap,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final String destination;
  final VoidCallback onDestinationTap;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('driving-to-destination-card'),
      padding: EdgeInsets.fromLTRB(
        28,
        10,
        28,
        MediaQuery.paddingOf(context).bottom + 18,
      ),
      decoration: const BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DriverSheetHandle(),
          const SizedBox(height: 18),
          const Text(
            'Driving to destination',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverVehicle ?? 'Vehicle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDEDED),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        driverPlate ?? '',
                        style: const TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              if (driverImage != null && driverImage!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(31),
                  child: Image.network(
                    driverImage!,
                    width: 56,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const CompatibleSvgPicture.asset(
                      'assets/images/driver_img.svg',
                      width: 56,
                      height: 62,
                    ),
                  ),
                )
              else
                const CompatibleSvgPicture.asset(
                  'assets/images/driver_img.svg',
                width: 56,
                height: 62,
                fit: BoxFit.contain,
                semanticsLabel: 'Driver profile',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Your driver is $driverName',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '20 finished rides',
            style: TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDestinationTap,
            child: Row(
              children: [
                const CompatibleSvgPicture.asset(
                  'assets/images/location icon.svg',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  semanticsLabel: 'Destination location icon',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination,
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
                      const SizedBox(height: 4),
                      const Text(
                        'Change Destination',
                        style: TextStyle(
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
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF3F414A),
                  size: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivingPanel extends StatefulWidget {
  const _ArrivingPanel({
    required this.pickupLocation,
    required this.destination,
    required this.sheetStage,
    required this.paymentMethod,
    required this.fareLabel,
    required this.onAdvance,
    required this.onRetreat,
    required this.onEditPickup,
    required this.onEditRoute,
    required this.onNotesTap,
    required this.onShareRide,
    required this.onCancelRide,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
    this.etaMinutes = 2,
  });

  final String pickupLocation;
  final String destination;
  final _ArrivingSheetStage sheetStage;
  final String paymentMethod;
  final String fareLabel;
  final VoidCallback onAdvance;
  final VoidCallback onRetreat;
  final VoidCallback onEditPickup;
  final VoidCallback onEditRoute;
  final VoidCallback onNotesTap;
  final VoidCallback onShareRide;
  final VoidCallback onCancelRide;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;
  final int etaMinutes;

  @override
  State<_ArrivingPanel> createState() => _ArrivingPanelState();
}

class _ArrivingPanelState extends State<_ArrivingPanel> {
  double _dragDistance = 0;

  bool get _isShowingDetails {
    return widget.sheetStage != _ArrivingSheetStage.collapsed;
  }

  bool get _isFullyExpanded {
    return widget.sheetStage == _ArrivingSheetStage.expanded;
  }

  String get _displayPickup {
    final value = widget.pickupLocation.trim();
    return value.isEmpty ? 'Current Location' : value;
  }

  String get _displayDestination {
    final value = widget.destination.trim();
    return value.isEmpty ? 'Ring Road Bus Terminal' : value;
  }

  void _startDrag(DragStartDetails details) {
    _dragDistance = 0;
  }

  void _trackDrag(DragUpdateDetails details) {
    _dragDistance += details.primaryDelta ?? 0;
  }

  void _finishDrag(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity < -250 || _dragDistance < -72) {
      widget.onAdvance();
    } else if (velocity > 250 || _dragDistance > 72) {
      widget.onRetreat();
    }
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('arriving-card'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _startDrag,
      onVerticalDragUpdate: _trackDrag,
      onVerticalDragEnd: _finishDrag,
      child: Container(
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
          children: [
            GestureDetector(
              key: const ValueKey('arriving-sheet-handle'),
              behavior: HitTestBehavior.opaque,
              onTap: _isFullyExpanded ? widget.onRetreat : widget.onAdvance,
              onVerticalDragStart: _startDrag,
              onVerticalDragUpdate: _trackDrag,
              onVerticalDragEnd: _finishDrag,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: _DriverSheetHandle(),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [...previousChildren, ?currentChild],
                  );
                },
                child: _isShowingDetails
                    ? _ArrivingExpandedContent(
                        key: ValueKey(
                          _isFullyExpanded
                              ? 'arriving-expanded-card'
                              : 'arriving-preview-card',
                        ),
                        pickupLocation: _displayPickup,
                        destination: _displayDestination,
                        showFullDetails: _isFullyExpanded,
                        paymentMethod: widget.paymentMethod,
                        fareLabel: widget.fareLabel,
                        onEditPickup: widget.onEditPickup,
                        onEditRoute: widget.onEditRoute,
                        onNotesTap: widget.onNotesTap,
                        onShareRide: widget.onShareRide,
                        onCancelRide: widget.onCancelRide,
                        driverName: widget.driverName,
                        driverImage: widget.driverImage,
                        driverVehicle: widget.driverVehicle,
                        driverPlate: widget.driverPlate,
                        etaMinutes: widget.etaMinutes,
                      )
                    : _ArrivingCollapsedContent(
                        key: const ValueKey('arriving-collapsed-card'),
                        pickupLocation: _displayPickup,
                        onEditPickup: widget.onEditPickup,
                        onNotesTap: widget.onNotesTap,
                        driverName: widget.driverName,
                        driverImage: widget.driverImage,
                        driverVehicle: widget.driverVehicle,
                        driverPlate: widget.driverPlate,
                        etaMinutes: widget.etaMinutes,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivingCollapsedContent extends StatelessWidget {
  const _ArrivingCollapsedContent({
    super.key,
    required this.pickupLocation,
    required this.onEditPickup,
    required this.onNotesTap,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
    this.etaMinutes = 2,
  });

  final String pickupLocation;
  final VoidCallback onEditPickup;
  final VoidCallback onNotesTap;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;
  final int etaMinutes;

  @override
  Widget build(BuildContext context) {
    final name = driverName.trim().isEmpty ? 'Driver' : driverName.trim();
    final mins = etaMinutes.clamp(1, 99);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          '$name is on the way',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Arriving In $mins mins',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8F8F8F),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 22),
        _ArrivingDriverInfo(
          leadingInset: 8,
          driverName: driverName,
          driverImage: driverImage,
          driverVehicle: driverVehicle,
          driverPlate: driverPlate,
        ),
        const SizedBox(height: 20),
        _PickupNotesAndCallRow(onNotesTap: onNotesTap, onCallTap: () {}),
        const SizedBox(height: 27),
        const Text(
          'My route',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 18),
        _RouteStopRow(
          marker: const _RoutePointMarker(),
          title: pickupLocation,
          trailing: _RoutePencilButton(
            semanticsLabel: 'Edit pickup location',
            onTap: onEditPickup,
          ),
        ),
      ],
    );
  }
}

class _ArrivingExpandedContent extends StatelessWidget {
  const _ArrivingExpandedContent({
    super.key,
    required this.pickupLocation,
    required this.destination,
    required this.showFullDetails,
    required this.paymentMethod,
    required this.fareLabel,
    required this.onEditPickup,
    required this.onEditRoute,
    required this.onNotesTap,
    required this.onShareRide,
    required this.onCancelRide,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
    this.etaMinutes = 2,
  });

  final String pickupLocation;
  final String destination;
  final bool showFullDetails;
  final String paymentMethod;
  final String fareLabel;
  final VoidCallback onEditPickup;
  final VoidCallback onEditRoute;
  final VoidCallback onNotesTap;
  final VoidCallback onShareRide;
  final VoidCallback onCancelRide;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;
  final int etaMinutes;

  @override
  Widget build(BuildContext context) {
    final name = driverName.trim().isEmpty ? 'Driver' : driverName.trim();
    final mins = etaMinutes.clamp(1, 99);
    return SingleChildScrollView(
      physics: showFullDetails
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            '$name is on the way',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Arriving In $mins mins',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          _ArrivingDriverInfo(
            leadingInset: 40,
            driverName: driverName,
            driverImage: driverImage,
            driverVehicle: driverVehicle,
            driverPlate: driverPlate,
          ),
          const SizedBox(height: 20),
          _PickupNotesAndCallRow(onNotesTap: onNotesTap, onCallTap: () {}),
          const SizedBox(height: 28),
          const Text(
            'My route',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          _ExpandedRouteDetails(
            pickupLocation: pickupLocation,
            destination: destination,
            onEditPickup: onEditPickup,
            onEditRoute: onEditRoute,
          ),
          const SizedBox(height: 18),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 20),
          _EditDestinationsRow(onTap: onEditRoute),
          const SizedBox(height: 30),
          const Text(
            'Payment Method',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          _PaymentMethodSummary(
            paymentMethod: paymentMethod,
            fareLabel: fareLabel,
          ),
          if (showFullDetails) ...[
            const SizedBox(height: 30),
            const Text(
              'More',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 18),
            _ArrivingMoreActionRow(
              iconAsset: 'assets/images/share ride icon.svg',
              label: 'Share ride details',
              semanticsLabel: 'Share ride details',
              onTap: onShareRide,
            ),
            const SizedBox(height: 10),
            _ArrivingMoreActionRow(
              iconAsset: 'assets/images/contact driver icon.svg',
              label: 'Contact driver',
              semanticsLabel: 'Contact driver',
              onTap: () {},
            ),
            const SizedBox(height: 10),
            _ArrivingMoreActionRow(
              iconAsset: 'assets/images/modal cancel ride icon.svg',
              label: 'Cancel ride',
              semanticsLabel: 'Cancel arriving ride',
              color: const Color(0xFFFF3838),
              onTap: onCancelRide,
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrivingDriverInfo extends StatelessWidget {
  const _ArrivingDriverInfo({
    required this.leadingInset,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final double leadingInset;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: leadingInset),
        if (driverImage != null && driverImage!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: Image.network(
              driverImage!,
              width: 56,
              height: 62,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const CompatibleSvgPicture.asset(
                'assets/images/driver_img.svg',
                width: 56,
                height: 62,
              ),
            ),
          )
        else
          const CompatibleSvgPicture.asset(
            'assets/images/driver_img.svg',
            width: 56,
            height: 62,
            fit: BoxFit.contain,
            semanticsLabel: 'Driver profile',
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 1),
              Text(
                driverName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              if (driverVehicle != null && driverVehicle!.isNotEmpty)
                Text(
                  driverVehicle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2C2D36),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              const SizedBox(height: 8),
              if (driverPlate != null && driverPlate!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    driverPlate!,
                    style: const TextStyle(
                      color: Color(0xFF565656),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArrivingMoreActionRow extends StatelessWidget {
  const _ArrivingMoreActionRow({
    required this.iconAsset,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
    this.color = AppColors.white,
  });

  final String iconAsset;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: CompatibleSvgPicture.asset(
                  iconAsset,
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverFlowMap extends StatefulWidget {
  const _DriverFlowMap({
    required this.pickupLatLng,
    required this.destinationLatLng,
    required this.routeSemanticsLabel,
    this.showNearbyCars = false,
    this.vehicleProgress,
    this.driverLatLng,
    this.driverHeading,
    this.vehicleAsset = 'assets/images/car.png',
    this.vehicleWidth = 44,
    this.vehicleHeight = 54,
    this.nearbyDrivers = const [],
    /// When true and [driverLatLng] is set, draw driver→pickup (on-the-way).
    this.routeDriverToPickup = false,
    this.onRouteDuration,
  });

  final LatLng? pickupLatLng;
  final LatLng? destinationLatLng;
  final String routeSemanticsLabel;
  final bool showNearbyCars;
  final double? vehicleProgress;
  final LatLng? driverLatLng;
  final double? driverHeading;
  final String vehicleAsset;
  final double vehicleWidth;
  final double vehicleHeight;
  final List<NearbyDriver> nearbyDrivers;
  final bool routeDriverToPickup;
  final ValueChanged<Duration>? onRouteDuration;

  @override
  State<_DriverFlowMap> createState() => _DriverFlowMapState();
}

class _DriverFlowMapState extends State<_DriverFlowMap> {
  final _routeService = CitirideRouteService();
  CitirideRoute? _route;
  bool _isLoadingRoute = false;
  int _routeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void didUpdateWidget(covariant _DriverFlowMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final endpointsChanged =
        !_sameLatLng(widget.pickupLatLng, oldWidget.pickupLatLng) ||
        !_sameLatLng(widget.destinationLatLng, oldWidget.destinationLatLng) ||
        widget.routeDriverToPickup != oldWidget.routeDriverToPickup;
    final driverMovedSignificantly = !_nearlySameLatLng(
      widget.driverLatLng,
      oldWidget.driverLatLng,
    );
    if (endpointsChanged ||
        (widget.routeDriverToPickup && driverMovedSignificantly)) {
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    final pickup = widget.pickupLatLng;
    final destination = widget.destinationLatLng;
    final driver = widget.driverLatLng;
    final generation = ++_routeGeneration;

    final LatLng? origin;
    final LatLng? target;
    if (widget.routeDriverToPickup && driver != null && pickup != null) {
      origin = driver;
      target = pickup;
    } else {
      origin = pickup;
      target = destination;
    }

    if (origin == null || target == null) {
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
      origin: origin,
      destination: target,
    );

    if (!mounted || generation != _routeGeneration) {
      return;
    }

    setState(() {
      _route = route;
      _isLoadingRoute = false;
    });
    widget.onRouteDuration?.call(route.duration);
  }

  bool _sameLatLng(LatLng? first, LatLng? second) {
    if (first == null || second == null) {
      return first == second;
    }

    return first.latitude == second.latitude &&
        first.longitude == second.longitude;
  }

  bool _nearlySameLatLng(LatLng? first, LatLng? second) {
    if (first == null || second == null) {
      return first == second;
    }
    // ~40m — avoid re-routing on every GPS tick.
    return (first.latitude - second.latitude).abs() < 0.00036 &&
        (first.longitude - second.longitude).abs() < 0.00036;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CitirideLiveRouteMap(
          fallbackSemanticsLabel: 'Driver flow map background',
          routeSemanticsLabel: widget.routeSemanticsLabel,
          route: _route,
          showCars: widget.showNearbyCars && widget.driverLatLng == null,
          showPickupPulse: true,
          vehicleProgress:
              widget.driverLatLng == null ? widget.vehicleProgress : null,
          vehiclePosition: widget.driverLatLng,
          vehicleHeading: widget.driverHeading,
          vehicleMarkerAsset: widget.vehicleAsset,
          vehicleMarkerWidth: widget.vehicleWidth,
          vehicleMarkerHeight: widget.vehicleHeight,
          cameraBoundsPadding: 132,
          fitRouteInView: true,
          nearbyDrivers: widget.nearbyDrivers,
        ),
        if (_isLoadingRoute)
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top + 112,
            child: const Center(child: _DriverRouteLoadingChip()),
          ),
      ],
    );
  }
}

class _DriverRouteLoadingChip extends StatelessWidget {
  const _DriverRouteLoadingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.citirideBlack.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.22)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          'Calculating route...',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LookingTopControls extends StatelessWidget {
  const _LookingTopControls({
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
        _LookingCircleButton(
          onTap: onClose,
          icon: Icons.close,
          semantics: 'Close looking for driver',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _LookingRouteSummaryPill(
            pickupLocation: pickupLocation,
            destination: destination,
            onTap: onEditRoute,
          ),
        ),
        const SizedBox(width: 4),
        _LookingAddStopButton(onTap: onAddStop),
      ],
    );
  }
}

class _LookingCircleButton extends StatelessWidget {
  const _LookingCircleButton({
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

class _LookingRouteSummaryPill extends StatelessWidget {
  const _LookingRouteSummaryPill({
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
                style: const TextStyle(
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

class _LookingAddStopButton extends StatelessWidget {
  const _LookingAddStopButton({required this.onTap});

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
            offset: const Offset(-25, -4),
            child: const CompatibleSvgPicture.asset(
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

class _LookingMyLocationButton extends StatelessWidget {
  const _LookingMyLocationButton();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _LookingForDriverPanel extends StatelessWidget {
  const _LookingForDriverPanel({
    required this.onEditPickup,
    required this.onCancelRide,
    this.statusMessage = 'Looking for a driver nearby',
  });

  final VoidCallback onEditPickup;
  final VoidCallback onCancelRide;
  final String statusMessage;

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
        children: [
          Container(
            width: 49,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE4E4EA),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Looking for Driver',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          const _LookingProgressBar(),
          const SizedBox(height: 16),
          _LookingActionsRow(
            leadingAsset: 'assets/images/Car_Icon.svg',
            leadingWidth: 48,
            leadingHeight: 48,
            leadingSemantics: 'Searching vehicle',
            onEditPickup: onEditPickup,
            onCancelRide: onCancelRide,
          ),
        ],
      ),
    );
  }
}

class _DriverFoundPanel extends StatelessWidget {
  const _DriverFoundPanel({
    required this.pickupLocation,
    required this.destination,
    required this.showDestinationChangeNotice,
    required this.isExpanded,
    required this.paymentMethod,
    required this.fareLabel,
    required this.onExpand,
    required this.onCollapse,
    required this.onEditPickup,
    required this.onEditRoute,
    required this.onNotesTap,
    required this.onCancelRide,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final String pickupLocation;
  final String destination;
  final bool showDestinationChangeNotice;
  final bool isExpanded;
  final String paymentMethod;
  final String fareLabel;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onEditPickup;
  final VoidCallback onEditRoute;
  final VoidCallback onNotesTap;
  final VoidCallback onCancelRide;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

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
      key: const ValueKey('driver-found-card'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        if (delta < -6) {
          onExpand();
        } else if (delta > 6) {
          onCollapse();
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.velocity.pixelsPerSecond.dy;
        if (velocity < -250) {
          onExpand();
        } else if (velocity > 250) {
          onCollapse();
        }
      },
      child: Container(
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: isExpanded
              ? _ExpandedDriverFoundContent(
                  key: const ValueKey('driver-found-expanded-card'),
                  pickupLocation: _displayPickup,
                  destination: _displayDestination,
                  showDestinationChangeNotice: showDestinationChangeNotice,
                  paymentMethod: paymentMethod,
                  fareLabel: fareLabel,
                  onEditPickup: onEditPickup,
                  onEditRoute: onEditRoute,
                  onNotesTap: onNotesTap,
                  onCollapse: onCollapse,
                  driverName: driverName,
                  driverImage: driverImage,
                  driverVehicle: driverVehicle,
                  driverPlate: driverPlate,
                )
              : _CollapsedDriverFoundContent(
                  key: const ValueKey('driver-found-collapsed-card'),
                  onEditPickup: onEditPickup,
                  onCancelRide: onCancelRide,
                ),
        ),
      ),
    );
  }
}

class _CollapsedDriverFoundContent extends StatelessWidget {
  const _CollapsedDriverFoundContent({
    super.key,
    required this.onEditPickup,
    required this.onCancelRide,
  });

  final VoidCallback onEditPickup;
  final VoidCallback onCancelRide;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _DriverSheetHandle(),
        const SizedBox(height: 14),
        const Text(
          'Driver found',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Waiting for driver to confirm the order',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF8F8F8F),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 20),
        const _LookingProgressBar(),
        const SizedBox(height: 16),
        _LookingActionsRow(
          leadingAsset: 'assets/images/driver_img.svg',
          leadingWidth: 48,
          leadingHeight: 53,
          leadingSemantics: 'Driver profile',
          onEditPickup: onEditPickup,
          onCancelRide: onCancelRide,
        ),
        const Spacer(),
        const Text(
          'My route',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ExpandedDriverFoundContent extends StatelessWidget {
  const _ExpandedDriverFoundContent({
    super.key,
    required this.pickupLocation,
    required this.destination,
    required this.showDestinationChangeNotice,
    required this.paymentMethod,
    required this.fareLabel,
    required this.onEditPickup,
    required this.onEditRoute,
    required this.onNotesTap,
    required this.onCollapse,
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final String pickupLocation;
  final String destination;
  final bool showDestinationChangeNotice;
  final String paymentMethod;
  final String fareLabel;
  final VoidCallback onEditPickup;
  final VoidCallback onEditRoute;
  final VoidCallback onNotesTap;
  final VoidCallback onCollapse;
  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            key: const ValueKey('driver-found-sheet-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: onCollapse,
            onVerticalDragUpdate: (details) {
              if ((details.primaryDelta ?? 0) > 4) {
                onCollapse();
              }
            },
            onVerticalDragEnd: (details) {
              if (details.velocity.pixelsPerSecond.dy > 180) {
                onCollapse();
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: _DriverSheetHandle(),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Driver found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          _ExpandedDriverInfo(
            driverName: driverName,
            driverImage: driverImage,
            driverVehicle: driverVehicle,
            driverPlate: driverPlate,
          ),
          const SizedBox(height: 20),
          _PickupNotesAndCallRow(onNotesTap: onNotesTap, onCallTap: () {}),
          const SizedBox(height: 28),
          const Text(
            'My route',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          _ExpandedRouteDetails(
            pickupLocation: pickupLocation,
            destination: destination,
            onEditPickup: onEditPickup,
            onEditRoute: onEditRoute,
          ),
          if (showDestinationChangeNotice) ...[
            const SizedBox(height: 14),
            const _DestinationChangeNotice(),
          ],
          const SizedBox(height: 18),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 20),
          _EditDestinationsRow(onTap: onEditRoute),
          const SizedBox(height: 30),
          const Text(
            'Payment Method',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          _PaymentMethodSummary(
            paymentMethod: paymentMethod,
            fareLabel: fareLabel,
          ),
        ],
      ),
    );
  }
}

class _DestinationChangeNotice extends StatelessWidget {
  const _DestinationChangeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.citirideYellow.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.citirideYellow.withValues(alpha: 0.45),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.citirideYellow, size: 18),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Price will change after the ride ends since destination has been changed.',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverSheetHandle extends StatelessWidget {
  const _DriverSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 49,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFE4E4EA),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _ExpandedDriverInfo extends StatelessWidget {
  const _ExpandedDriverInfo({
    this.driverName = 'Driver',
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 40),
        if (driverImage != null && driverImage!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: Image.network(
              driverImage!,
              width: 56,
              height: 62,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const CompatibleSvgPicture.asset(
                'assets/images/driver_img.svg',
                width: 56,
                height: 62,
              ),
            ),
          )
        else
          const CompatibleSvgPicture.asset(
            'assets/images/driver_img.svg',
            width: 56,
            height: 62,
            fit: BoxFit.contain,
            semanticsLabel: 'Driver profile',
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 1),
              Text(
                driverName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              if (driverVehicle != null && driverVehicle!.isNotEmpty)
                Text(
                  driverVehicle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2C2D36),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              const SizedBox(height: 8),
              if (driverPlate != null && driverPlate!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    driverPlate!,
                    style: const TextStyle(
                      color: Color(0xFF565656),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _shareRideMessage({
  required String pickupLocation,
  required String destination,
  String driverName = 'my driver',
  String? driverVehicle,
  String? driverPlate,
}) {
  final vehicleInfo = [
    if (driverVehicle != null && driverVehicle.isNotEmpty) driverVehicle,
    if (driverPlate != null && driverPlate.isNotEmpty) '($driverPlate)',
  ].join(' ');
  final vehiclePart = vehicleInfo.isNotEmpty ? ' in a $vehicleInfo' : '';
  return 'I am taking a CitiRide trip with $driverName$vehiclePart. Pickup: $pickupLocation. Destination: $destination. Follow this ride in real time from my CitiRide app.';
}

Future<void> _showShareRideDetails(
  BuildContext context, {
  required String pickupLocation,
  required String destination,
  String driverName = 'my driver',
  String? driverVehicle,
  String? driverPlate,
}) async {
  final message = _shareRideMessage(
    pickupLocation: pickupLocation,
    destination: destination,
    driverName: driverName,
    driverVehicle: driverVehicle,
    driverPlate: driverPlate,
  );

  final shouldShare = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) {
      return _ShareRideDetailsSheet(
        onShareRide: () => Navigator.of(sheetContext).pop(true),
      );
    },
  );

  if (shouldShare != true || !context.mounted) {
    return;
  }

  await _shareRideNatively(context, message);
}

Future<void> _shareRideNatively(BuildContext context, String message) async {
  final params = await _buildShareRideParams(context, message);
  final launcher = debugShareRideLauncher ?? _launchNativeShare;
  await launcher(params);
}

Future<void> _launchNativeShare(ShareParams params) async {
  await SharePlus.instance.share(params);
}

Future<ShareParams> _buildShareRideParams(
  BuildContext context,
  String message,
) async {
  final origin = _sharePositionOrigin(context);

  try {
    final screenshot = await rootBundle.load('assets/images/screenshot.svg');
    final bytes = screenshot.buffer.asUint8List(
      screenshot.offsetInBytes,
      screenshot.lengthInBytes,
    );

    return ShareParams(
      title: 'CitiRide ride details',
      subject: 'My CitiRide ride details',
      text: message,
      files: [XFile.fromData(bytes, mimeType: 'image/svg+xml')],
      fileNameOverrides: ['citiride-ride-details.svg'],
      sharePositionOrigin: origin,
    );
  } on FlutterError {
    return ShareParams(
      title: 'CitiRide ride details',
      subject: 'My CitiRide ride details',
      text: message,
      sharePositionOrigin: origin,
    );
  }
}

Rect? _sharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }

  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

class _ShareRideDetailsSheet extends StatelessWidget {
  const _ShareRideDetailsSheet({required this.onShareRide});

  final VoidCallback onShareRide;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final sheetHeight = math.min(
      462.0 + bottomInset,
      MediaQuery.sizeOf(context).height * 0.60,
    );

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          key: const ValueKey('share-ride-details-sheet'),
          padding: EdgeInsets.fromLTRB(20, 9, 20, bottomInset + 18),
          decoration: const BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: _DriverSheetHandle(),
              ),
              Positioned(
                right: 0,
                top: 3,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: IconButton(
                    key: const ValueKey('share-ride-sheet-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    splashRadius: 22,
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 1.4),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: 31,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Share ride details',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Follow this ride in real-time by sharing your ride\ndetails with the screenshot',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9C9C9C),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Center(child: _ShareRideScreenshotPreview()),
                    const Spacer(),
                    SizedBox(
                      height: 49,
                      child: FilledButton(
                        key: const ValueKey('share-ride-button'),
                        onPressed: onShareRide,
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
                        child: const Text('Share ride'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareRideScreenshotPreview extends StatelessWidget {
  const _ShareRideScreenshotPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 226,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const CompatibleSvgPicture.asset(
        'assets/images/screenshot.svg',
        fit: BoxFit.contain,
        semanticsLabel: 'Share ride screenshot',
      ),
    );
  }
}

Future<void> _showPickupNotesChat(
  BuildContext context, {
  required String driverName,
  String? driverImage,
  String? driverVehicle,
  String? driverPlate,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close pickup notes chat',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _PickupNotesChatOverlay(
        driverName: driverName,
        driverImage: driverImage,
        driverVehicle: driverVehicle,
        driverPlate: driverPlate,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isRider});

  final String text;
  final bool isRider;
}

class _PickupNotesChatOverlay extends StatefulWidget {
  const _PickupNotesChatOverlay({
    required this.driverName,
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
  });

  final String driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;

  @override
  State<_PickupNotesChatOverlay> createState() =>
      _PickupNotesChatOverlayState();
}

class _PickupNotesChatOverlayState extends State<_PickupNotesChatOverlay> {
  static const _quickMessages = <String>[
    'Hi, where are you',
    "I'm here",
    "I'm on my way",
  ];
  static const _emojiOptions = <String>[
    '\u{1F600}',
    '\u{1F601}',
    '\u{1F602}',
    '\u{1F923}',
    '\u{1F642}',
    '\u{1F60A}',
    '\u{1F60D}',
    '\u{1F929}',
    '\u{1F60E}',
    '\u{1F914}',
    '\u{1F62D}',
    '\u{1F621}',
    '\u{1F44D}',
    '\u{1F44E}',
    '\u{1F44B}',
    '\u{1F64F}',
    '\u{1F44C}',
    '\u{1F91D}',
    '\u{1F4AA}',
    '\u{1F448}',
    '\u{1F449}',
    '\u{1F446}',
    '\u{1F447}',
    '\u{1F64C}',
    '\u{1F697}',
    '\u{1F695}',
    '\u{1F698}',
    '\u{1F68C}',
    '\u{1F6B6}',
    '\u{1F3C3}',
    '\u{1F4CD}',
    '\u{1F4CC}',
    '\u{1F3E0}',
    '\u{1F3E2}',
    '\u{1F6A6}',
    '\u{1F6E3}',
    '\u{23F0}',
    '\u{1F552}',
    '\u{1F4B5}',
    '\u{1F4B3}',
    '\u{1F4AC}',
    '\u{1F4DE}',
    '\u{1F4AF}',
    '\u{2728}',
    '\u{2705}',
    '\u{274C}',
    '\u{26A0}',
    '\u{1F525}',
  ];

  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  bool _showEmojiBox = false;

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _sendQuickMessage(String message) {
    _sendMessage(message == "I'm on my way" ? "Hi, I'm on my way" : message);
  }

  void _sendTypedMessage() {
    _sendMessage(_messageController.text);
  }

  void _sendMessage(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      return;
    }

    final shouldAddDriverReply = !_messages.any((entry) => !entry.isRider);
    _messageController.clear();
    setState(() {
      _showEmojiBox = false;
      _messages.add(_ChatMessage(text: message, isRider: true));
      if (shouldAddDriverReply) {
        _messages.add(
          const _ChatMessage(text: 'Alright, coming soon', isRider: false),
        );
      }
    });
  }

  void _toggleEmojiBox() {
    setState(() {
      _showEmojiBox = !_showEmojiBox;
    });
  }

  void _insertEmoji(String emoji) {
    final value = _messageController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final updatedText = value.text.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _messageFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final panelTop = math.max(mediaQuery.padding.top + 18, 64.0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
                12,
                panelTop,
                12,
                mediaQuery.viewInsets.bottom,
              ),
              child: Container(
                key: const ValueKey('pickup-notes-chat-modal'),
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: AppColors.citirideBlack,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    7,
                    8,
                    mediaQuery.padding.bottom + 22,
                  ),
                  child: Column(
                    children: [
                      const _DriverSheetHandle(),
                      const SizedBox(height: 16),
                      _buildHeader(context),
                      _buildConversationArea(),
                      if (_showEmojiBox) ...[
                        _buildEmojiBox(),
                        const SizedBox(height: 10),
                      ],
                      _buildComposer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 57,
      padding: const EdgeInsets.fromLTRB(8, 5, 7, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(29),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 32,
              height: 47,
              child: Icon(Icons.arrow_back, color: AppColors.white, size: 24),
            ),
          ),
          const SizedBox(width: 4),
          if (widget.driverImage != null && widget.driverImage!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Image.network(
                widget.driverImage!,
                width: 38,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const CompatibleSvgPicture.asset(
                  'assets/images/driver_img.svg',
                  width: 38,
                  height: 42,
                ),
              ),
            )
          else
            const CompatibleSvgPicture.asset(
              'assets/images/driver_img.svg',
              width: 38,
              height: 42,
              fit: BoxFit.contain,
              semanticsLabel: 'Driver profile',
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.driverName.trim().isEmpty
                      ? 'Driver'
                      : widget.driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    widget.driverVehicle?.trim(),
                    widget.driverPlate?.trim(),
                  ]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9A9A9A),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const CompatibleSvgPicture.asset(
            'assets/images/phone icon.svg',
            width: 51,
            height: 51,
            fit: BoxFit.contain,
            semanticsLabel: 'Call driver',
          ),
        ],
      ),
    );
  }

  Widget _buildConversationArea() {
    if (_messages.isNotEmpty) {
      return _buildMessages();
    }

    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildQuickMessages(),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return const Expanded(child: SizedBox.shrink());
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return Align(
            alignment: message.isRider
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 205),
              margin: EdgeInsets.only(
                left: message.isRider ? 60 : 0,
                right: message.isRider ? 0 : 60,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: message.isRider
                    ? AppColors.citirideYellow
                    : const Color(0xFFEFEFEF),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: Color(0xFF161616),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemCount: _messages.length,
      ),
    );
  }

  Widget _buildQuickMessages() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final message in _quickMessages)
            SizedBox(
              width: _quickMessageWidth(message),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _sendQuickMessage(message),
                child: Container(
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFF9D9D9D)),
                  ),
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9D9D9D),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _quickMessageWidth(String message) {
    return switch (message) {
      'Hi, where are you' => 119,
      "I'm here" => 68,
      _ => 101,
    };
  }

  Widget _buildEmojiBox() {
    return Container(
      key: const ValueKey('pickup-chat-emoji-box'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.25)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 156),
        child: SingleChildScrollView(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final emoji in _emojiOptions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _insertEmoji(emoji),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22, height: 1),
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

  Widget _buildComposer() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.white),
            ),
            child: Row(
              children: [
                const CompatibleSvgPicture.asset(
                  'assets/images/pickup notes icon.svg',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  semanticsLabel: 'Pickup notes icon',
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: const ValueKey('pickup-chat-emoji-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleEmojiBox,
                  child: const SizedBox(
                    width: 24,
                    height: 25,
                    child: Icon(
                      Icons.emoji_emotions_outlined,
                      color: Color(0xFF9A9A9A),
                      size: 23,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('pickup-chat-message-field'),
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    cursorColor: AppColors.citirideYellow,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type your message',
                      hintStyle: TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      fillColor: Colors.transparent,
                      isDense: true,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendTypedMessage(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 15),
        GestureDetector(
          key: const ValueKey('pickup-chat-send-button'),
          behavior: HitTestBehavior.opaque,
          onTap: _sendTypedMessage,
          child: const CompatibleSvgPicture.asset(
            'assets/images/send message icon.svg',
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            semanticsLabel: 'Send message',
          ),
        ),
      ],
    );
  }
}

class _PickupNotesAndCallRow extends StatelessWidget {
  const _PickupNotesAndCallRow({
    required this.onNotesTap,
    required this.onCallTap,
  });

  final VoidCallback onNotesTap;
  final VoidCallback onCallTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Add pickup notes',
            child: GestureDetector(
              key: const ValueKey('pickup-notes-field'),
              behavior: HitTestBehavior.opaque,
              onTap: onNotesTap,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 17),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.white),
                ),
                child: const Row(
                  children: [
                    CompatibleSvgPicture.asset(
                      'assets/images/pickup notes icon.svg',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      semanticsLabel: 'Pickup notes icon',
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Any pickup notes?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF8F8F8F),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCallTap,
          child: const CompatibleSvgPicture.asset(
            'assets/images/phone icon.svg',
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            semanticsLabel: 'Call driver',
          ),
        ),
      ],
    );
  }
}

class _ExpandedRouteDetails extends StatelessWidget {
  const _ExpandedRouteDetails({
    required this.pickupLocation,
    required this.destination,
    required this.onEditPickup,
    required this.onEditRoute,
  });

  final String pickupLocation;
  final String destination;
  final VoidCallback onEditPickup;
  final VoidCallback onEditRoute;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: Stack(
        children: [
          Positioned(
            left: 15,
            top: 11,
            bottom: 11,
            child: Container(width: 1, color: const Color(0xFF8F8F8F)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _RouteStopRow(
              marker: const _RoutePointMarker(),
              title: pickupLocation,
              trailing: _RoutePencilButton(
                semanticsLabel: 'Edit pickup location',
                onTap: onEditPickup,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 46,
            child: const _RouteStopRow(
              marker: CompatibleSvgPicture.asset(
                'assets/images/modal addstop icon.svg',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                semanticsLabel: 'Add stop icon',
              ),
              title: 'Add stop',
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 92,
            child: _RouteStopRow(
              marker: const CompatibleSvgPicture.asset(
                'assets/images/location icon.svg',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                semanticsLabel: 'Destination location icon',
              ),
              title: destination,
              trailing: _RoutePencilButton(
                semanticsLabel: 'Edit destination',
                onTap: onEditRoute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({
    required this.marker,
    required this.title,
    this.trailing,
  });

  final Widget marker;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 31, child: Center(child: marker)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _RoutePointMarker extends StatelessWidget {
  const _RoutePointMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: AppColors.citirideYellow,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white, width: 2),
      ),
    );
  }
}

class _RoutePencilButton extends StatelessWidget {
  const _RoutePencilButton({required this.semanticsLabel, required this.onTap});

  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(
          width: 36,
          height: 30,
          child: Align(
            alignment: Alignment.centerRight,
            child: CompatibleSvgPicture.asset(
              'assets/images/pencil icon.svg',
              width: 20,
              height: 20,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditDestinationsRow extends StatelessWidget {
  const _EditDestinationsRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const Row(
        children: [
          CompatibleSvgPicture.asset(
            'assets/images/edit pickup icon.svg',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            semanticsLabel: 'Edit destinations icon',
          ),
          SizedBox(width: 14),
          Text(
            'Edit Destinations',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodSummary extends StatelessWidget {
  const _PaymentMethodSummary({
    required this.paymentMethod,
    required this.fareLabel,
  });

  final String paymentMethod;
  final String fareLabel;

  @override
  Widget build(BuildContext context) {
    final isWallet = paymentMethod.trim().toLowerCase() == 'wallet';
    final title = isWallet ? 'CitiRide Wallet' : 'Cash';
    final iconAsset = isWallet
        ? 'assets/images/wallet icon.svg'
        : 'assets/images/cash icon.svg';

    return Row(
      children: [
        CompatibleSvgPicture.asset(
          iconAsset,
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          semanticsLabel: '$title payment icon',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ),
        Text(
          fareLabel,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _LookingProgressBar extends StatefulWidget {
  const _LookingProgressBar();

  @override
  State<_LookingProgressBar> createState() => _LookingProgressBarState();
}

class _LookingProgressBarState extends State<_LookingProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: double.infinity,
        height: 4,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = math.min(
              constraints.maxWidth * 0.58,
              math.max(92.0, constraints.maxWidth * 0.38),
            );
            final travel = math.max(0.0, constraints.maxWidth - segmentWidth);

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final eased = Curves.easeInOut.transform(_controller.value);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFD9EEFF)),
                    ),
                    Positioned(
                      left: travel * eased,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.citirideYellow,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LookingActionsRow extends StatelessWidget {
  const _LookingActionsRow({
    required this.leadingAsset,
    required this.leadingWidth,
    required this.leadingHeight,
    required this.leadingSemantics,
    required this.onEditPickup,
    required this.onCancelRide,
  });

  final String leadingAsset;
  final double leadingWidth;
  final double leadingHeight;
  final String leadingSemantics;
  final VoidCallback onEditPickup;
  final VoidCallback onCancelRide;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Semantics(
            label: leadingSemantics,
            image: true,
            container: true,
            excludeSemantics: true,
            child: Center(
              child: CompatibleSvgPicture.asset(
                leadingAsset,
                width: leadingWidth,
                height: leadingHeight,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        _LookingActionButton(
          iconAsset: 'assets/images/edit pickup icon.svg',
          label: 'Edit pickup',
          semanticsLabel: 'Edit pickup',
          onTap: onEditPickup,
        ),
        _LookingActionButton(
          iconAsset: 'assets/images/cancel ride icon.svg',
          label: 'Cancel Ride',
          semanticsLabel: 'Cancel ride',
          onTap: onCancelRide,
        ),
      ],
    );
  }
}

class _LookingActionButton extends StatelessWidget {
  const _LookingActionButton({
    required this.iconAsset,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey(
          'looking-action-${semanticsLabel.toLowerCase().replaceAll(' ', '-')}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              CompatibleSvgPicture.asset(
                iconAsset,
                width: 48,
                height: 48,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 8,
                  fontWeight: FontWeight.w400,
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

class _ArrivingCancelRideSheet extends StatelessWidget {
  const _ArrivingCancelRideSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final sheetHeight = math.min(
      352.0 + bottomInset,
      MediaQuery.sizeOf(context).height * 0.45,
    );

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          key: const ValueKey('arriving-cancel-ride-sheet'),
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 18),
          decoration: const BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 49,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E4EA),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 3,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: IconButton(
                    key: const ValueKey('arriving-cancel-sheet-close'),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    splashRadius: 22,
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 1.4),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: 34,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Are you sure?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 13),
                    const Text(
                      "Do you want to cancel the ride? You will be\ncharged a fee to compensate for the\ndriver's time",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9C9C9C),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cancellation fee',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          '\u20A6350',
                          style: TextStyle(
                            color: Color(0xFFFF3838),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 49,
                      child: FilledButton(
                        key: const ValueKey('arriving-confirm-cancel-button'),
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3838),
                          foregroundColor: AppColors.white,
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
                        child: const Text('Cancel ride'),
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      height: 49,
                      child: FilledButton(
                        key: const ValueKey('arriving-wait-driver-button'),
                        onPressed: () => Navigator.of(context).pop(false),
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
                        child: const Text('Wait for driver'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelRideSheet extends StatelessWidget {
  const _CancelRideSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 49,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4EA),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),
            const CompatibleSvgPicture.asset(
              'assets/images/modal cancel ride icon.svg',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              semanticsLabel: 'Cancel ride warning',
            ),
            const SizedBox(height: 18),
            const Text(
              'Cancel ride request?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'We are still looking for a driver nearby. Canceling now will stop this ride request.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9C9C9C),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: FilledButton(
                key: const ValueKey('confirm-cancel-ride-button'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3838),
                  foregroundColor: AppColors.white,
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
                child: const Text('Cancel Ride'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: FilledButton(
                key: const ValueKey('keep-ride-button'),
                onPressed: () => Navigator.of(context).pop(false),
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
                child: const Text('Keep Ride'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
