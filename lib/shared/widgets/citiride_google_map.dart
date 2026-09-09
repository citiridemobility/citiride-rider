import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../core/maps/google_maps_config.dart';
import '../../core/maps/google_maps_js_loader.dart';

class CitirideGoogleMap extends StatefulWidget {
  const CitirideGoogleMap({
    super.key,
    required this.fallback,
    required this.fallbackSemanticsLabel,
    this.cameraTarget,
    this.cameraBounds,
    this.cameraBoundsPadding = 72,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onMapTap,
    this.onCameraMove,
    this.onCameraIdle,
    this.myLocationEnabled = false,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
  });

  final Widget fallback;
  final String fallbackSemanticsLabel;
  final LatLng? cameraTarget;
  final LatLngBounds? cameraBounds;
  final double cameraBoundsPadding;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final ValueChanged<LatLng>? onMapTap;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraIdle;
  final bool myLocationEnabled;
  final bool scrollGesturesEnabled;
  final bool zoomGesturesEnabled;
  final bool rotateGesturesEnabled;

  @override
  State<CitirideGoogleMap> createState() => _CitirideGoogleMapState();
}

class _CitirideGoogleMapState extends State<CitirideGoogleMap> {
  late Future<bool> _mapsSdkReady;
  final _controller = Completer<GoogleMapController>();
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _mapsSdkReady = _loadMapsSdk();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CitirideGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bounds = widget.cameraBounds;
    if (bounds != null && !_sameBounds(bounds, oldWidget.cameraBounds)) {
      _fitBounds(bounds);
      return;
    }

    final target = widget.cameraTarget;
    if (target != null && !_sameLatLng(target, oldWidget.cameraTarget)) {
      _moveCamera(target);
    }
  }

  Future<bool> _loadMapsSdk() async {
    final apiKey = await GoogleMapsConfig.runtimeApiKey();
    if (!GoogleMapsConfig.isUsableApiKey(apiKey)) {
      return false;
    }

    // Web must wait until google.maps.MapTypeId exists; building GoogleMap
    // earlier yields ROADMAP TypeErrors / blank tiles.
    if (kIsWeb) {
      return ensureGoogleMapsJsSdk(apiKey: apiKey!);
    }

    return true;
  }

  Future<void> _moveCamera(LatLng target) async {
    if (!_controller.isCompleted) {
      return;
    }

    await _applyCameraUpdate(CameraUpdate.newLatLng(target));
  }

  Future<void> _fitBounds(LatLngBounds bounds) async {
    if (!_controller.isCompleted) {
      return;
    }

    await _applyCameraUpdate(
      CameraUpdate.newLatLngBounds(bounds, widget.cameraBoundsPadding),
    );
  }

  Future<void> _applyCameraUpdate(CameraUpdate update) async {
    if (!_controller.isCompleted) {
      return;
    }

    try {
      final controller = await _controller.future;
      await controller.animateCamera(update);
    } on Object {
      // Google Maps can briefly reject camera updates before the native view is sized.
    }
  }

  Future<void> _moveCameraWithoutAnimation(CameraUpdate update) async {
    if (!_controller.isCompleted) {
      return;
    }

    try {
      final controller = await _controller.future;
      await controller.moveCamera(update);
    } on Object {
      // Keep first map mount resilient on Android surface lifecycle edges.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _mapsSdkReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFF141414),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.citirideYellow,
                ),
              ),
            ),
          );
        }

        if (snapshot.data != true) {
          return _fallbackMap();
        }

        return _googleMap();
      },
    );
  }

  Widget _fallbackMap() {
    return Semantics(
      label: widget.fallbackSemanticsLabel,
      child: widget.fallback,
    );
  }

  Widget _googleMap() {
    final target = widget.cameraTarget ?? GoogleMapsConfig.defaultCenter;

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: target,
        zoom: GoogleMapsConfig.defaultZoom,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (!_controller.isCompleted) {
          _controller.complete(controller);
        }
        widget.onMapCreated?.call(controller);

        final bounds = widget.cameraBounds;
        if (bounds != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(
                _moveCameraWithoutAnimation(
                  CameraUpdate.newLatLngBounds(
                    bounds,
                    widget.cameraBoundsPadding,
                  ),
                ),
              );
            }
          });
          return;
        }

        final target = widget.cameraTarget;
        if (target != null) {
          unawaited(
            _moveCameraWithoutAnimation(CameraUpdate.newLatLng(target)),
          );
        }
      },
      // JSON map styles are unreliable on google_maps_flutter_web (blank tiles).
      style: kIsWeb ? null : _darkMapStyle,
      markers: widget.markers,
      polylines: widget.polylines,
      onTap: widget.onMapTap,
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
      myLocationEnabled: !kIsWeb && widget.myLocationEnabled,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: kIsWeb,
      scrollGesturesEnabled: widget.scrollGesturesEnabled,
      zoomGesturesEnabled: widget.zoomGesturesEnabled,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      buildingsEnabled: false,
      trafficEnabled: false,
      tiltGesturesEnabled: false,
    );
  }

  bool _sameLatLng(LatLng? first, LatLng? second) {
    if (first == null || second == null) {
      return first == second;
    }

    return first.latitude == second.latitude &&
        first.longitude == second.longitude;
  }

  bool _sameBounds(LatLngBounds? first, LatLngBounds? second) {
    if (first == null || second == null) {
      return first == second;
    }

    return _sameLatLng(first.southwest, second.southwest) &&
        _sameLatLng(first.northeast, second.northeast);
  }
}

Marker citirideLocationMarker({
  required String markerId,
  required LatLng position,
  String title = 'Current location',
  double hue = BitmapDescriptor.hueYellow,
}) {
  return Marker(
    markerId: MarkerId(markerId),
    position: position,
    infoWindow: InfoWindow(title: title),
    icon: BitmapDescriptor.defaultMarkerWithHue(hue),
  );
}

Polyline citirideRoutePolyline(List<LatLng> points) {
  return Polyline(
    polylineId: const PolylineId('citiride-route'),
    points: points,
    color: AppColors.citirideYellow,
    width: kIsWeb ? 5 : 7,
    geodesic: true,
    jointType: JointType.round,
    startCap: Cap.roundCap,
    endCap: Cap.roundCap,
    zIndex: 1,
  );
}

/// Soft underlay that makes the yellow route read cleaner on dark basemaps.
Polyline citirideRoutePolylineOutline(List<LatLng> points) {
  return Polyline(
    polylineId: const PolylineId('citiride-route-outline'),
    points: points,
    color: const Color(0xE6000000),
    width: kIsWeb ? 9 : 12,
    geodesic: true,
    jointType: JointType.round,
    startCap: Cap.roundCap,
    endCap: Cap.roundCap,
    zIndex: 0,
  );
}

Set<Polyline> citirideRoutePolylines(List<LatLng> points) {
  if (points.length < 2) {
    return const <Polyline>{};
  }
  return <Polyline>{
    citirideRoutePolylineOutline(points),
    citirideRoutePolyline(points),
  };
}

const _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#141414"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6f6f6f"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#141414"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#191919"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#121212"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#111111"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#777777"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#303030"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#202020"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]}
]
''';
