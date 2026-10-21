import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../core/location/citiride_route.dart';
import '../../features/ride/domain/live_ride.dart';
import 'citiride_google_map.dart';
import 'citiride_location_status_pulse.dart';
import 'compatible_svg_picture.dart';

class CitirideLiveRouteMap extends StatefulWidget {
  const CitirideLiveRouteMap({
    super.key,
    required this.fallbackSemanticsLabel,
    required this.routeSemanticsLabel,
    this.route,
    this.showCars = false,
    this.showPickupPulse = false,
    this.showPickupMarker = true,
    this.showDestinationMarker = true,
    this.pickupLabelBuilder,
    this.destinationLabelBuilder,
    this.vehicleProgress,
    this.vehiclePosition,
    this.vehicleHeading,
    this.vehicleMarkerAsset = 'assets/images/car.png',
    this.vehicleMarkerWidth = 44,
    this.vehicleMarkerHeight = 54,
    this.cameraBoundsPadding = 104,
    this.fitRouteInView = true,
    this.cameraFocus,
    this.cameraZoom,
    this.mapPadding = EdgeInsets.zero,
    this.nearbyDrivers = const [],
    this.onMapTap,
    this.onCameraMove,
    this.onCameraIdle,
  });

  final String fallbackSemanticsLabel;
  final String routeSemanticsLabel;
  final CitirideRoute? route;
  final bool showCars;
  final bool showPickupPulse;
  final bool showPickupMarker;
  final bool showDestinationMarker;
  final String Function(CitirideRoute route)? pickupLabelBuilder;
  final String Function(CitirideRoute route)? destinationLabelBuilder;
  final double? vehicleProgress;

  /// Real nearby driver positions from Firestore.
  final List<NearbyDriver> nearbyDrivers;

  /// Absolute GPS for the assigned driver (preferred over [vehicleProgress]).
  final LatLng? vehiclePosition;
  final double? vehicleHeading;
  final String vehicleMarkerAsset;
  final double vehicleMarkerWidth;
  final double vehicleMarkerHeight;
  final double cameraBoundsPadding;

  /// When false, route updates do not re-fit/recenter the camera (used while
  /// the rider is manually positioning pickup under the center pin).
  final bool fitRouteInView;

  /// Optional camera target. Pickup selection uses the pickup point so the
  /// center pin sits on the route start instead of the destination/midpoint.
  final LatLng? cameraFocus;
  final double? cameraZoom;
  final EdgeInsets mapPadding;
  final ValueChanged<LatLng>? onMapTap;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraIdle;

  static const designSize = Size(390, 844);
  @override
  State<CitirideLiveRouteMap> createState() => _CitirideLiveRouteMapState();
}

class _CitirideLiveRouteMapState extends State<CitirideLiveRouteMap> {
  Future<_RouteMarkerIcons>? _markerIcons;
  GoogleMapController? _mapController;
  Offset? _pickupScreen;
  Offset? _destinationScreen;
  int _overlayGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
  }

  @override
  void didUpdateWidget(covariant CitirideLiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.route?.arrivalText != oldWidget.route?.arrivalText ||
        widget.route?.pickupEtaText != oldWidget.route?.pickupEtaText ||
        _pickupLabel(widget.route) != _pickupLabel(oldWidget.route) ||
        _destinationLabel(widget.route) != _destinationLabel(oldWidget.route) ||
        widget.showCars != oldWidget.showCars ||
        widget.showPickupPulse != oldWidget.showPickupPulse ||
        widget.vehicleProgress != oldWidget.vehicleProgress ||
        widget.vehiclePosition != oldWidget.vehiclePosition ||
        widget.vehicleHeading != oldWidget.vehicleHeading ||
        widget.vehicleMarkerAsset != oldWidget.vehicleMarkerAsset ||
        widget.vehicleMarkerWidth != oldWidget.vehicleMarkerWidth ||
        widget.vehicleMarkerHeight != oldWidget.vehicleMarkerHeight ||
        (widget.route != null && oldWidget.route == null)) {
      _loadMarkerIcons();
    }

    if (widget.route != oldWidget.route ||
        widget.cameraBoundsPadding != oldWidget.cameraBoundsPadding ||
        widget.fitRouteInView != oldWidget.fitRouteInView) {
      unawaited(_refreshOverlayPositions());
    }
  }

  String _pickupLabel(CitirideRoute? route) {
    if (route == null) {
      return '';
    }
    return widget.pickupLabelBuilder?.call(route) ?? route.pickupEtaText;
  }

  String _destinationLabel(CitirideRoute? route) {
    if (route == null) {
      return '';
    }
    return widget.destinationLabelBuilder?.call(route) ?? route.arrivalText;
  }

  void _loadMarkerIcons() {
    final route = widget.route;
    if (route == null &&
        !widget.showCars &&
        widget.vehicleProgress == null &&
        widget.vehiclePosition == null) {
      _markerIcons = null;
      return;
    }

    _markerIcons = _RouteMarkerIcons.create(
      vehicleAssetName: widget.vehicleMarkerAsset,
      vehicleWidth: widget.vehicleMarkerWidth,
      vehicleHeight: widget.vehicleMarkerHeight,
    );
  }

  Future<void> _refreshOverlayPositions() async {
    final controller = _mapController;
    final route = widget.route;
    final generation = ++_overlayGeneration;
    if (controller == null || route == null || !mounted) {
      return;
    }

    try {
      final pickup = await controller.getScreenCoordinate(route.routeStart);
      final destination = await controller.getScreenCoordinate(route.routeEnd);
      if (!mounted || generation != _overlayGeneration) {
        return;
      }

      // Mobile SDKs return physical pixels; Flutter layout uses logical pixels.
      // The web implementation already returns CSS/logical pixels — don't scale.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final scale = kIsWeb || dpr <= 0 ? 1.0 : dpr;

      setState(() {
        _pickupScreen = Offset(pickup.x / scale, pickup.y / scale);
        _destinationScreen = Offset(
          destination.x / scale,
          destination.y / scale,
        );
      });
    } on Object {
      // Projection can fail briefly while the map surface is resizing.
    }
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    unawaited(_refreshOverlayPositions());
  }

  void _handleCameraMove(CameraPosition position) {
    widget.onCameraMove?.call(position);
    unawaited(_refreshOverlayPositions());
  }

  void _handleCameraIdle() {
    widget.onCameraIdle?.call();
    unawaited(_refreshOverlayPositions());
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final pickupLabel = _pickupLabel(route);
    final destinationLabel = _destinationLabel(route);
    // Screen-projected overlays need a live GoogleMap controller (mobile + web).
    final useMapOverlays = _mapController != null;
    final showPickupOverlay =
        useMapOverlays &&
        route != null &&
        (widget.showPickupMarker || widget.showPickupPulse);

    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<_RouteMarkerIcons>(
          future: _markerIcons,
          builder: (context, snapshot) {
            final icons = snapshot.data;

            return CitirideGoogleMap(
              fallback: _FallbackRouteMap(
                route: route,
                showPickupPulse: widget.showPickupPulse,
                showDestinationMarker: widget.showDestinationMarker,
                routeSemanticsLabel: widget.routeSemanticsLabel,
                pickupLabel: pickupLabel,
                destinationLabel: widget.showDestinationMarker
                    ? destinationLabel
                    : '',
              ),
              fallbackSemanticsLabel: widget.fallbackSemanticsLabel,
              cameraTarget:
                  widget.vehiclePosition ??
                  widget.cameraFocus ??
                  (widget.fitRouteInView ? route?.center : route?.routeStart),
              cameraZoom: widget.cameraZoom,
              cameraBounds:
                  widget.fitRouteInView &&
                      widget.vehiclePosition == null &&
                      widget.cameraFocus == null
                  ? route?.latLngBounds
                  : null,
              cameraBoundsPadding: widget.cameraBoundsPadding,
              padding: widget.mapPadding,
              onMapCreated: _handleMapCreated,
              markers: {
                if (icons != null && widget.vehiclePosition != null)
                  Marker(
                    markerId: const MarkerId('citiride-route-vehicle'),
                    position: widget.vehiclePosition!,
                    icon: icons.vehicle,
                    anchor: const Offset(0.5, 0.5),
                    flat: true,
                    rotation: _vehicleRotation(widget.vehicleHeading ?? 0),
                    zIndexInt: 5,
                  ),
                if (route != null && icons != null) ...{
                  // Prefer Flutter overlay (label + pin). Native pin only while
                  // screen projection is still resolving.
                  if (widget.showDestinationMarker &&
                      _destinationScreen == null)
                    Marker(
                      markerId: const MarkerId(
                        'citiride-route-destination-pin',
                      ),
                      position: route.routeEnd,
                      icon: icons.destinationPin,
                      anchor: const Offset(0.5, 0.5),
                      zIndexInt: 4,
                    ),
                  if (widget.showPickupMarker &&
                      !widget.showPickupPulse &&
                      _pickupScreen == null)
                    Marker(
                      markerId: const MarkerId('citiride-route-pickup-pin'),
                      position: route.routeStart,
                      icon: icons.pickupPin,
                      anchor: const Offset(0.5, 0.5),
                      zIndexInt: 3,
                    ),
                  if (widget.vehiclePosition == null &&
                      widget.vehicleProgress != null)
                    _routeVehicleMarker(
                      route,
                      icons.vehicle,
                      widget.vehicleProgress!,
                    ),
                  if (widget.showCars &&
                      widget.vehiclePosition == null &&
                      widget.nearbyDrivers.isNotEmpty)
                    ..._realNearbyVehicleMarkers(
                      widget.nearbyDrivers,
                      icons.vehicle,
                    ),
                  ..._routeDirectionArrowMarkers(route, icons.arrow),
                },
              },
              onMapTap: widget.onMapTap,
              onCameraMove: _handleCameraMove,
              onCameraIdle: _handleCameraIdle,
              polylines: {
                if (route != null) ...citirideRoutePolylines(route.points),
              },
            );
          },
        ),
        if (showPickupOverlay && _pickupScreen != null)
          _RoutePointOverlay(
            point: _pickupScreen!,
            label: pickupLabel,
            showPulse: widget.showPickupPulse,
            showStem: true,
          ),
        if (widget.showDestinationMarker &&
            useMapOverlays &&
            route != null &&
            destinationLabel.trim().isNotEmpty &&
            _destinationScreen != null)
          _RoutePointOverlay(
            point: _destinationScreen!,
            label: destinationLabel,
            showPulse: false,
            showStem: true,
          ),
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: Text(
              widget.routeSemanticsLabel,
              semanticsLabel: widget.routeSemanticsLabel,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoutePointOverlay extends StatelessWidget {
  const _RoutePointOverlay({
    required this.point,
    required this.label,
    required this.showPulse,
    required this.showStem,
  });

  final Offset point;
  final String label;
  final bool showPulse;
  final bool showStem;

  @override
  Widget build(BuildContext context) {
    final cleanLabel = label.trim();
    const pulseSize = 72.0;
    const labelHeight = 23.0;
    final labelWidth = cleanLabel.isEmpty
        ? 0.0
        : math.min(168.0, math.max(64.0, cleanLabel.length * 7.1 + 24));

    return IgnorePointer(
      child: Stack(
        children: [
          if (showPulse)
            Positioned(
              left: point.dx - pulseSize / 2,
              top: point.dy - pulseSize / 2,
              child: const CitirideLocationStatusPulse(
                size: pulseSize,
                iconSize: 44,
              ),
            ),
          if (showStem && cleanLabel.isNotEmpty)
            Positioned(
              left: point.dx - 1,
              top: point.dy - 34,
              child: Container(
                width: 2,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2A2A),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          // Anchor dot on the route endpoint (under the label stem).
          if (!showPulse)
            Positioned(
              left: point.dx - 6,
              top: point.dy - 6,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.citirideYellow, width: 3),
                ),
              ),
            ),
          if (cleanLabel.isNotEmpty)
            Positioned(
              left: point.dx - labelWidth / 2,
              top: point.dy - 56,
              width: labelWidth,
              height: labelHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.citirideYellow,
                  borderRadius: BorderRadius.circular(11.5),
                ),
                child: Center(
                  child: Text(
                    cleanLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.citirideBlack,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
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
}

class _FallbackRouteMap extends StatelessWidget {
  const _FallbackRouteMap({
    required this.route,
    required this.showPickupPulse,
    required this.showDestinationMarker,
    required this.routeSemanticsLabel,
    required this.pickupLabel,
    required this.destinationLabel,
  });

  final CitirideRoute? route;
  final bool showPickupPulse;
  final bool showDestinationMarker;
  final String routeSemanticsLabel;
  final String pickupLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF050505),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.max(
            constraints.maxWidth / CitirideLiveRouteMap.designSize.width,
            constraints.maxHeight / CitirideLiveRouteMap.designSize.height,
          );
          final artWidth = CitirideLiveRouteMap.designSize.width * scale;
          final artHeight = CitirideLiveRouteMap.designSize.height * scale;
          final artLeft = (constraints.maxWidth - artWidth) / 2;
          final artTop = (constraints.maxHeight - artHeight) / 2;

          // Design-space pickup point from map direction SVG (approx. 113, 470
          // inside the 390x844 artboard after the route strip offsets).
          final pickupDesign = Offset(
            artLeft + (78 + 35) * scale,
            artTop + (135 + 165) * scale,
          );
          const pulseSize = 72.0;

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: routeSemanticsLabel,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: artLeft,
                  top: artTop,
                  width: artWidth,
                  height: artHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const CompatibleSvgPicture.asset(
                        'assets/images/Basemap image.svg',
                        fit: BoxFit.fill,
                        semanticsLabel: 'Route basemap',
                      ),
                      if (route != null)
                        Semantics(
                          label: routeSemanticsLabel,
                          child: CustomPaint(
                            painter: _FallbackRoutePainter(
                              route: route!,
                              pickupLabel: pickupLabel,
                              destinationLabel: destinationLabel,
                              drawPickupPin: !showPickupPulse,
                              drawDestinationPin: showDestinationMarker,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                    ],
                  ),
                ),
                if (route != null && showPickupPulse)
                  Positioned(
                    left: pickupDesign.dx - pulseSize / 2,
                    top: pickupDesign.dy - pulseSize / 2,
                    child: const CitirideLocationStatusPulse(
                      size: pulseSize,
                      iconSize: 44,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Marker _routeVehicleMarker(
  CitirideRoute route,
  BitmapDescriptor icon,
  double progress,
) {
  final vehicle = _pointAlongPolyline(
    route.points,
    progress.clamp(0.0, 1.0).toDouble(),
  );

  return Marker(
    markerId: const MarkerId('citiride-route-vehicle'),
    position: vehicle.position,
    icon: icon,
    anchor: const Offset(0.5, 0.5),
    flat: true,
    rotation: _vehicleRotation(vehicle.heading),
    zIndexInt: 5,
  );
}

Set<Marker> _realNearbyVehicleMarkers(
  List<NearbyDriver> drivers,
  BitmapDescriptor icon,
) {
  return {
    for (var i = 0; i < drivers.length; i += 1)
      Marker(
        markerId: MarkerId('citiride-nearby-driver-${drivers[i].driverId}'),
        position: LatLng(drivers[i].lat, drivers[i].lng),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _vehicleRotation(drivers[i].heading),
        zIndexInt: 2,
      ),
  };
}

Set<Marker> _routeDirectionArrowMarkers(
  CitirideRoute route,
  BitmapDescriptor icon,
) {
  final arrows = _directionArrowPoints(route.points);
  return {
    for (var i = 0; i < arrows.length; i += 1)
      Marker(
        markerId: MarkerId('citiride-route-arrow-$i'),
        position: arrows[i].position,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _vehicleRotation(arrows[i].heading),
        zIndexInt: 1,
      ),
  };
}

/// Google Maps rotation is clockwise from north. Vehicle and arrow bitmaps
/// are drawn with the nose/tip pointing up, so heading maps 1:1.
double _vehicleRotation(double heading) {
  if (heading.isNaN || heading < 0) {
    return 0;
  }
  return heading % 360;
}

List<_RoutePolylinePoint> _directionArrowPoints(List<LatLng> points) {
  if (points.length < 2) {
    return const [];
  }

  var totalDistance = 0.0;
  for (var i = 0; i < points.length - 1; i += 1) {
    totalDistance += _distanceMeters(points[i], points[i + 1]);
  }
  if (totalDistance < 45) {
    return const [];
  }

  final spacing = math.max(70.0, math.min(140.0, totalDistance / 6));
  final startAt = math.min(48.0, totalDistance * 0.14);
  final endAt = math.max(startAt + 24, totalDistance - 32);
  final arrows = <_RoutePolylinePoint>[];
  var next = startAt;
  while (next < endAt && arrows.length < 12) {
    arrows.add(
      _pointAlongPolyline(points, (next / totalDistance).clamp(0.0, 1.0)),
    );
    next += spacing;
  }
  return arrows;
}

_RoutePolylinePoint _pointAlongPolyline(List<LatLng> points, double progress) {
  if (points.length < 2) {
    final point = points.isEmpty ? const LatLng(6.3350, 5.6037) : points.first;
    return _RoutePolylinePoint(position: point, heading: 0);
  }

  final segments = <_PolylineSegment>[];
  var totalDistance = 0.0;
  for (var i = 0; i < points.length - 1; i += 1) {
    final start = points[i];
    final end = points[i + 1];
    final distance = _distanceMeters(start, end);
    if (distance <= 0) {
      continue;
    }
    totalDistance += distance;
    segments.add(
      _PolylineSegment(start: start, end: end, distanceMeters: distance),
    );
  }

  if (segments.isEmpty || totalDistance <= 0) {
    return _RoutePolylinePoint(position: points.first, heading: 0);
  }

  var targetDistance = totalDistance * progress;
  for (final segment in segments) {
    if (targetDistance > segment.distanceMeters) {
      targetDistance -= segment.distanceMeters;
      continue;
    }

    final ratio = targetDistance / segment.distanceMeters;
    final position = LatLng(
      segment.start.latitude +
          (segment.end.latitude - segment.start.latitude) * ratio,
      segment.start.longitude +
          (segment.end.longitude - segment.start.longitude) * ratio,
    );

    return _RoutePolylinePoint(
      position: position,
      heading: _bearingDegrees(segment.start, segment.end),
    );
  }

  final lastSegment = segments.last;
  return _RoutePolylinePoint(
    position: lastSegment.end,
    heading: _bearingDegrees(lastSegment.start, lastSegment.end),
  );
}

double _distanceMeters(LatLng first, LatLng second) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = _radians(first.latitude);
  final lat2 = _radians(second.latitude);
  final deltaLat = _radians(second.latitude - first.latitude);
  final deltaLng = _radians(second.longitude - first.longitude);
  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _bearingDegrees(LatLng start, LatLng end) {
  final startLat = _radians(start.latitude);
  final endLat = _radians(end.latitude);
  final deltaLng = _radians(end.longitude - start.longitude);
  final y = math.sin(deltaLng) * math.cos(endLat);
  final x =
      math.cos(startLat) * math.sin(endLat) -
      math.sin(startLat) * math.cos(endLat) * math.cos(deltaLng);
  return ((_degrees(math.atan2(y, x)) + 360) % 360);
}

double _radians(double degrees) => degrees * math.pi / 180;

double _degrees(double radians) => radians * 180 / math.pi;

class _PolylineSegment {
  const _PolylineSegment({
    required this.start,
    required this.end,
    required this.distanceMeters,
  });

  final LatLng start;
  final LatLng end;
  final double distanceMeters;
}

class _RoutePolylinePoint {
  const _RoutePolylinePoint({required this.position, required this.heading});

  final LatLng position;
  final double heading;
}

class _FallbackRoutePainter extends CustomPainter {
  const _FallbackRoutePainter({
    required this.route,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.drawPickupPin,
    required this.drawDestinationPin,
  });

  final CitirideRoute route;
  final String pickupLabel;
  final String destinationLabel;
  final bool drawPickupPin;
  final bool drawDestinationPin;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 390, size.height / 844);
    final left = (size.width - (390 * scale)) / 2 + 78 * scale;
    final top = (size.height - (844 * scale)) / 2 + 135 * scale;
    Offset mapPoint(double x, double y) =>
        Offset(left + x * scale, top + y * scale);

    final start = mapPoint(35, 165);
    final end = mapPoint(176, 43);

    final path = Path()
      ..moveTo(mapPoint(39, 154).dx, mapPoint(39, 154).dy)
      ..cubicTo(
        mapPoint(40.28, 149.39).dx,
        mapPoint(40.28, 149.39).dy,
        mapPoint(45.51, 147.17).dx,
        mapPoint(45.51, 147.17).dy,
        mapPoint(49.72, 149.44).dx,
        mapPoint(49.72, 149.44).dy,
      )
      ..lineTo(mapPoint(91.27, 171.87).dx, mapPoint(91.27, 171.87).dy)
      ..cubicTo(
        mapPoint(95.03, 173.90).dx,
        mapPoint(95.03, 173.90).dy,
        mapPoint(99.73, 172.61).dx,
        mapPoint(99.73, 172.61).dy,
        mapPoint(101.93, 168.93).dx,
        mapPoint(101.93, 168.93).dy,
      )
      ..lineTo(mapPoint(177, 43.5).dx, mapPoint(177, 43.5).dy);

    final line = Paint()
      ..color = AppColors.citirideYellow
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);

    _drawLabeledPin(
      canvas,
      start,
      pickupLabel,
      withHalo: drawPickupPin,
      drawPin: drawPickupPin,
    );
    _drawLabeledPin(
      canvas,
      end,
      destinationLabel,
      withHalo: false,
      drawPin: drawDestinationPin,
    );
  }

  void _drawLabeledPin(
    Canvas canvas,
    Offset point,
    String label, {
    required bool withHalo,
    required bool drawPin,
  }) {
    if (drawPin) {
      if (withHalo) {
        canvas.drawCircle(
          point,
          32,
          Paint()..color = AppColors.citirideYellow.withValues(alpha: 0.2),
        );
      }

      canvas.drawCircle(point, 12, Paint()..color = AppColors.white);
      canvas.drawCircle(
        point,
        7,
        Paint()
          ..color = AppColors.citirideYellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    final clean = label.trim();
    if (clean.isEmpty) {
      return;
    }

    final paragraph = _paragraph(clean);
    paragraph.layout(const ui.ParagraphConstraints(width: 160));
    final width = math.min(
      160.0,
      math.max(64.0, paragraph.maxIntrinsicWidth + 24),
    );
    final pillTop = point.dy - 42;
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(point.dx, pillTop),
        width: width,
        height: 23,
      ),
      const Radius.circular(11.5),
    );
    canvas.drawRRect(pill, Paint()..color = AppColors.citirideYellow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(point.dx, (pillTop + 11.5 + point.dy - 12) / 2),
          width: 2,
          height: math.max(8, point.dy - 12 - (pillTop + 11.5)),
        ),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF2E2A2A),
    );
    canvas.drawParagraph(
      paragraph,
      Offset(point.dx - paragraph.maxIntrinsicWidth / 2, pillTop - 5.5),
    );
  }

  ui.Paragraph _paragraph(String text) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              maxLines: 1,
              ellipsis: '...',
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: AppColors.citirideBlack,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          )
          ..addText(text);
    return builder.build();
  }

  @override
  bool shouldRepaint(covariant _FallbackRoutePainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.pickupLabel != pickupLabel ||
        oldDelegate.destinationLabel != destinationLabel ||
        oldDelegate.drawPickupPin != drawPickupPin ||
        oldDelegate.drawDestinationPin != drawDestinationPin;
  }
}

class _RouteMarkerIcons {
  const _RouteMarkerIcons({
    required this.pickupPin,
    required this.destinationPin,
    required this.vehicle,
    required this.arrow,
  });

  final BitmapDescriptor pickupPin;
  final BitmapDescriptor destinationPin;
  final BitmapDescriptor vehicle;
  final BitmapDescriptor arrow;

  static Future<_RouteMarkerIcons> create({
    required String vehicleAssetName,
    required double vehicleWidth,
    required double vehicleHeight,
  }) async {
    final pickupPin = await _dotPin(hasHalo: true);
    final destinationPin = await _dotPin(hasHalo: false);
    final vehicle = await _vehicleIcon(
      vehicleAssetName,
      vehicleWidth,
      vehicleHeight,
    );
    final arrow = await _directionArrowIcon();
    return _RouteMarkerIcons(
      pickupPin: pickupPin,
      destinationPin: destinationPin,
      vehicle: vehicle,
      arrow: arrow,
    );
  }

  static Future<BitmapDescriptor> _dotPin({required bool hasHalo}) async {
    const dpr = 3.0;
    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final center = const Offset(size / 2, size / 2);

    if (hasHalo) {
      canvas.drawCircle(
        center,
        22,
        Paint()..color = AppColors.citirideYellow.withValues(alpha: 0.2),
      );
    }
    canvas.drawCircle(center, 11, Paint()..color = AppColors.white);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = AppColors.citirideYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    final image = await recorder.endRecording().toImage(
      (size * dpr).round(),
      (size * dpr).round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    if (bytes.isEmpty) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }

    return BitmapDescriptor.bytes(bytes, width: size, height: size);
  }

  static Future<BitmapDescriptor> _directionArrowIcon() async {
    const logicalSize = 18.0;
    const dpr = 3.0;
    final pixelSize = (logicalSize * dpr).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    final chevron = Path()
      ..moveTo(logicalSize / 2, 1.5)
      ..lineTo(logicalSize - 2.5, logicalSize - 3.5)
      ..lineTo(logicalSize / 2, logicalSize * 0.58)
      ..lineTo(2.5, logicalSize - 3.5)
      ..close();

    canvas.drawPath(
      chevron,
      Paint()
        ..color = const Color(0xE6000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(chevron, Paint()..color = AppColors.citirideYellow);

    final image = await recorder.endRecording().toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    if (bytes.isEmpty) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
    return BitmapDescriptor.bytes(
      bytes,
      width: logicalSize,
      height: logicalSize,
    );
  }

  static Future<BitmapDescriptor> _vehicleIcon(
    String assetName,
    double width,
    double height,
  ) async {
    try {
      if (assetName.toLowerCase().endsWith('.png')) {
        // The supplied vehicle bitmap is already a north-facing, transparent
        // marker. Keep it unmodified so a GPS heading of 0 points up.
        return await BitmapDescriptor.asset(
          ImageConfiguration(size: Size(width, height)),
          assetName,
          width: width,
          height: height,
        );
      }

      final rawSvg = await rootBundle.loadString(assetName);
      final normalizedSvg = CompatibleSvgPicture.normalizeSvgForRuntime(rawSvg);
      final pictureInfo = await vg.loadPicture(
        SvgStringLoader(normalizedSvg),
        null,
      );
      final landscape = await pictureInfo.picture.toImage(
        (width * 3).round(),
        (height * 3).round(),
      );
      pictureInfo.picture.dispose();

      // The car asset is drawn nose-right. Rotate it nose-up so Maps heading
      // (0 = north) points the vehicle in the direction of travel.
      final squareLogical = math.max(width, height);
      final squarePx = (squareLogical * 3).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(squarePx / 2, squarePx / 2);
      canvas.rotate(-math.pi / 2);
      canvas.drawImageRect(
        landscape,
        Rect.fromLTWH(
          0,
          0,
          landscape.width.toDouble(),
          landscape.height.toDouble(),
        ),
        Rect.fromCenter(
          center: Offset.zero,
          width: width * 3,
          height: height * 3,
        ),
        Paint()..filterQuality = FilterQuality.high,
      );
      final image = await recorder.endRecording().toImage(squarePx, squarePx);
      landscape.dispose();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
      if (bytes.isEmpty) {
        return BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueYellow,
        );
      }

      return BitmapDescriptor.bytes(
        bytes,
        width: squareLogical,
        height: squareLogical,
      );
    } on Object {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }
}
