import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/location/citiride_place.dart';
import '../../../core/location/live_location_service.dart';
import '../../../core/location/location_search_history_store.dart';
import '../../../core/location/places_service.dart';
import '../../../core/location/route_query.dart';
import '../../profile/domain/rider_profile.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../../shared/widgets/citiride_bottom_nav.dart';
import '../../../shared/widgets/citiride_google_map.dart';
import '../../../shared/widgets/citiride_location_status_pulse.dart';
import '../../../shared/widgets/citiride_logout_dialog.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

enum _HomeSheetPosition { collapsed, preview, expanded }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialLocationLabel,
    this.initialLocation,
  });

  final String? initialLocationLabel;
  final LatLng? initialLocation;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _locationService = const LiveLocationService();
  final _placesService = CitiridePlacesService();
  StreamSubscription<LatLng>? _locationSubscription;
  LatLng? _lastAddressLookupLocation;
  int _addressLookupVersion = 0;
  LatLng? _currentLocation;
  String _locationLabel = 'Set location';
  _HomeSheetPosition _sheetPosition = _HomeSheetPosition.collapsed;
  double _sheetDragDelta = 0;
  List<CitiridePlace> _recentPlaces = const [];

  bool _isProfileSidebarOpen = false;
  bool _isNotificationsPeekOpen = false;
  bool get _isRunningWidgetTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void initState() {
    super.initState();
    final initialLocation = widget.initialLocation;
    if (initialLocation != null) {
      _currentLocation = initialLocation;
      final label = widget.initialLocationLabel?.trim();
      _locationLabel = label == null || label.isEmpty
          ? 'My location'
          : label;
    }
    if (_isRunningWidgetTest) {
      unawaited(_loadRecentPlaces());
      return;
    }

    unawaited(_loadRecentPlaces());
    unawaited(_startLocationTracking());
  }

  Future<void> _loadRecentPlaces() async {
    final places = await const LocationSearchHistoryStore().load();
    if (!mounted) {
      return;
    }
    setState(() {
      _recentPlaces = places;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    if (mounted && _currentLocation == null) {
      setState(() {
        _locationLabel = 'Locating...';
      });
    }

    final lastKnownLocation = await _locationService
        .lastKnownLatLng(requestIfDenied: true)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (lastKnownLocation != null) {
      _updateCurrentLocation(lastKnownLocation);
    }

    final currentLocation = await _locationService
        .currentLatLng(requestIfDenied: true)
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
    if (currentLocation != null) {
      _updateCurrentLocation(currentLocation);
    } else if (mounted) {
      setState(() {
        if (_currentLocation == null) {
          _locationLabel = 'Set location';
        }
      });
    }

    _locationSubscription = _locationService
        .watchLatLng(requestIfDenied: true)
        .listen(_updateCurrentLocation, onError: (_) {});
  }

  void _updateCurrentLocation(LatLng location) {
    if (!mounted) {
      return;
    }

    setState(() {
      _currentLocation = location;
      if (_locationLabel == 'Set location') {
        _locationLabel = 'Locating...';
      }
    });

    if (_shouldRefreshLocationLabel(location)) {
      unawaited(_resolveCurrentLocationLabel(location));
    }
  }

  bool _shouldRefreshLocationLabel(LatLng location) {
    final lastLookup = _lastAddressLookupLocation;
    if (lastLookup == null) {
      return true;
    }

    const threshold = 0.00018;
    return (location.latitude - lastLookup.latitude).abs() > threshold ||
        (location.longitude - lastLookup.longitude).abs() > threshold;
  }

  Future<void> _resolveCurrentLocationLabel(LatLng location) async {
    _lastAddressLookupLocation = location;
    final lookupVersion = ++_addressLookupVersion;
    final label = await _placesService
        .reverseGeocodeLabel(location)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);

    if (!mounted || lookupVersion != _addressLookupVersion) {
      return;
    }

    setState(() {
      _locationLabel = label?.trim().isNotEmpty == true
          ? label!.trim()
          : 'My location';
    });
  }

  void _openRouteSearch({CitiridePlace? destination}) {
    final location = _currentLocation;
    final queryParameters = <String, String>{};
    if (location != null) {
      final label = _locationLabel.trim();
      final pickupLabel =
          label.isEmpty ||
              label == 'Locating...' ||
              label == 'Set location'
          ? 'My location'
          : label;
      queryParameters.addAll({
        'pickup': pickupLabel,
        ...latLngToQuery('pickup', location),
      });
    }
    if (destination != null && destination.title.trim().isNotEmpty) {
      queryParameters['destination'] = destination.title.trim();
      queryParameters.addAll(latLngToQuery('destination', destination.location));
    }

    unawaited(
      context
          .push(Uri(path: '/route', queryParameters: queryParameters).toString())
          .then((_) {
            if (mounted) {
              unawaited(_loadRecentPlaces());
            }
          }),
    );
  }

  void _openProfileSidebar() {
    setState(() {
      _isProfileSidebarOpen = true;
    });
  }

  void _closeProfileSidebar() {
    if (!_isProfileSidebarOpen) {
      return;
    }

    setState(() {
      _isProfileSidebarOpen = false;
    });
  }

  void _openNotificationsPeek() {
    setState(() {
      _isNotificationsPeekOpen = true;
    });
  }

  void _closeNotificationsPeek() {
    if (!_isNotificationsPeekOpen) {
      return;
    }

    setState(() {
      _isNotificationsPeekOpen = false;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _sheetDragDelta += details.delta.dy;
  }

  void _handleDragEnd(DragEndDetails details) {
    _settleSheet(details.primaryVelocity ?? 0);
  }

  void _settleSheet(double velocity) {
    final shouldExpand = _sheetDragDelta < -42 || velocity < -260;
    final shouldCollapse = _sheetDragDelta > 42 || velocity > 260;

    setState(() {
      if (shouldExpand) {
        _sheetPosition = switch (_sheetPosition) {
          _HomeSheetPosition.collapsed => _HomeSheetPosition.preview,
          _HomeSheetPosition.preview => _HomeSheetPosition.expanded,
          _HomeSheetPosition.expanded => _HomeSheetPosition.expanded,
        };
      } else if (shouldCollapse) {
        _sheetPosition = switch (_sheetPosition) {
          _HomeSheetPosition.collapsed => _HomeSheetPosition.collapsed,
          _HomeSheetPosition.preview => _HomeSheetPosition.collapsed,
          _HomeSheetPosition.expanded => _HomeSheetPosition.preview,
        };
      }
      _sheetDragDelta = 0;
    });
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
            final bottomOffset = _sheetBottomOffset(constraints.maxHeight);
            final horizontalInset =
                _sheetPosition == _HomeSheetPosition.collapsed ? 20.0 : 12.0;
            final sheetHeight = _sheetHeight(constraints.maxHeight);

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _HomeMapBackground(
                    currentLocation: _currentLocation,
                    showLocationStatus: true,
                  ),
                ),
                const Positioned.fill(child: _HomeBackgroundUiCleanup()),
                Positioned(
                  left: 22,
                  right: 22,
                  top: math.max(MediaQuery.paddingOf(context).top + 4, 48),
                  child: _HomeTopControls(
                    locationLabel: _locationLabel,
                    onProfileTap: _openProfileSidebar,
                    onNotificationsTap: _openNotificationsPeek,
                    onLocationTap: () {
                      unawaited(_startLocationTracking());
                    },
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 39,
                  child: Center(child: _HomeBottomNavigation()),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: horizontalInset,
                  right: horizontalInset,
                  bottom: bottomOffset,
                  height: sheetHeight,
                  child: SizedBox.expand(
                    key: ValueKey('home-search-sheet-${_sheetPosition.name}'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _handleDragUpdate,
                      onVerticalDragEnd: _handleDragEnd,
                      child: _HomeSearchPanel(
                        position: _sheetPosition,
                        recentPlaces: _recentPlaces,
                        onSearchTap: _openRouteSearch,
                        onRecentTap: (place) =>
                            _openRouteSearch(destination: place),
                      ),
                    ),
                  ),
                ),
                if (_isProfileSidebarOpen)
                  Positioned.fill(
                    child: _ProfileSidebarOverlay(
                      onClose: _closeProfileSidebar,
                    ),
                  ),
                if (_isNotificationsPeekOpen)
                  Positioned.fill(
                    child: NotificationsPeekOverlay(
                      onClose: _closeNotificationsPeek,
                      onViewAll: () {
                        _closeNotificationsPeek();
                        context.push('/notifications');
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _sheetBottomOffset(double screenHeight) {
    return switch (_sheetPosition) {
      _HomeSheetPosition.collapsed => 112,
      _ => math.min(116.0, screenHeight * 0.137),
    };
  }

  double _sheetHeight(double screenHeight) {
    return switch (_sheetPosition) {
      _HomeSheetPosition.collapsed => 96,
      _HomeSheetPosition.preview => 274,
      _HomeSheetPosition.expanded => math.min(
        594,
        math.max(430, screenHeight * 0.704),
      ),
    };
  }
}

class _HomeMapBackground extends StatelessWidget {
  const _HomeMapBackground({
    this.currentLocation,
    required this.showLocationStatus,
  });

  final LatLng? currentLocation;
  final bool showLocationStatus;

  static const _designSize = Size(390, 844);
  static const _carsFrame = Rect.fromLTWH(24, 164, 347, 455);

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: const Color(0xFF050505),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.max(
            constraints.maxWidth / _designSize.width,
            constraints.maxHeight / _designSize.height,
          );
          final artWidth = _designSize.width * scale;
          final artHeight = _designSize.height * scale;
          final artLeft = (constraints.maxWidth - artWidth) / 2;
          final artTop = (constraints.maxHeight - artHeight) / 2;

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
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
                        semanticsLabel: 'Home basemap',
                      ),
                      Positioned(
                        left: _carsFrame.left * scale,
                        top: _carsFrame.top * scale,
                        width: _carsFrame.width * scale,
                        height: _carsFrame.height * scale,
                        child: const CompatibleSvgPicture.asset(
                          'assets/images/Cars.svg',
                          fit: BoxFit.fill,
                          semanticsLabel: 'Map cars',
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.03),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return KeyedSubtree(
      key: const ValueKey('home-map-background'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CitirideGoogleMap(
            fallback: fallback,
            fallbackSemanticsLabel: 'Home map background',
            cameraTarget: currentLocation,
            myLocationEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
          ),
          if (showLocationStatus)
            const IgnorePointer(
              child: Center(child: CitirideLocationStatusPulse()),
            ),
        ],
      ),
    );
  }
}

class _HomeBackgroundUiCleanup extends StatelessWidget {
  const _HomeBackgroundUiCleanup();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: math.min(132, constraints.maxHeight * 0.16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.42),
                        Colors.black.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: math.min(224, constraints.maxHeight * 0.27),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.38),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeTopControls extends StatelessWidget {
  const _HomeTopControls({
    required this.locationLabel,
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onLocationTap,
  });

  final String locationLabel;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Open profile menu',
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              key: const ValueKey('home-profile-button'),
              onTap: onProfileTap,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.citirideYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: ValueListenableBuilder<RiderProfile>(
                    valueListenable: RiderProfileStore.instance.profile,
                    builder: (context, profile, _) {
                      return _HomeProfileAvatarImage(profile: profile);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Refresh current location',
          child: GestureDetector(
            onTap: onLocationTap,
            child: Container(
              width: 174,
              height: 50,
              padding: const EdgeInsets.fromLTRB(11, 6, 16, 6),
              decoration: BoxDecoration(
                color: AppColors.citirideBlack,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AppColors.white),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 23,
                    height: 23,
                    child: CompatibleSvgPicture.asset(
                      'assets/images/location icon.svg',
                      fit: BoxFit.contain,
                      semanticsLabel: 'Current location icon',
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF8F8F8F),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Open notifications',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('home-notifications-button'),
              onTap: onNotificationsTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 52,
                height: 52,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 85,
                  maxWidth: 85,
                  minHeight: 139,
                  maxHeight: 139,
                  child: Transform.translate(
                    offset: const Offset(-23, -2),
                    child: const CompatibleSvgPicture.asset(
                      'assets/images/Notifications.svg',
                      width: 85,
                      height: 139,
                      fit: BoxFit.fill,
                      semanticsLabel: 'Notifications',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeProfileAvatarImage extends StatelessWidget {
  const _HomeProfileAvatarImage({required this.profile});

  final RiderProfile profile;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 42,
        height: 42,
        child: profile.photoBytes == null
            ? const CompatibleSvgPicture.asset(
                'assets/images/Profile.svg',
                fit: BoxFit.contain,
                semanticsLabel: 'Profile avatar',
              )
            : Image.memory(profile.photoBytes!, fit: BoxFit.cover),
      ),
    );
  }
}

class _ProfileSidebarOverlay extends StatelessWidget {
  const _ProfileSidebarOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = math.min(304.0, constraints.maxWidth * 0.78);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('profile-sidebar-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.66),
                  ),
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: -1, end: 0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(value * panelWidth, 0),
                  child: child,
                );
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: _ProfileSidebar(width: panelWidth, onClose: onClose),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileSidebar extends StatelessWidget {
  const _ProfileSidebar({required this.width, required this.onClose});

  final double width;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 28,
              offset: const Offset(16, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<RiderProfile>(
                  valueListenable: RiderProfileStore.instance.profile,
                  builder: (context, profile, _) {
                    return _ProfileSidebarHeader(
                      profile: profile,
                      onClose: onClose,
                    );
                  },
                ),
                const SizedBox(height: 32),
                ValueListenableBuilder<RiderProfile>(
                  valueListenable: RiderProfileStore.instance.profile,
                  builder: (context, profile, _) {
                    return _ProfileMenuItem(
                      icon: Icons.person,
                      title: profile.hasCompletedPersonalInfo
                          ? 'Edit profile info'
                          : 'Personal info',
                      subtitle: 'Edit your personal information',
                      onTap: () => context.push('/personal-info'),
                    );
                  },
                ),
                const SizedBox(height: 22),
                _ProfileMenuItem(
                  icon: Icons.settings,
                  title: 'Settings',
                  subtitle: 'Edit your settings',
                  onTap: () => context.push('/settings'),
                ),
                // Saved places is paused for now.
                // const SizedBox(height: 22),
                // const _ProfileMenuItem(
                //   icon: Icons.home_work,
                //   title: 'Saved places',
                //   subtitle: 'Enter your home and work location',
                // ),
                const SizedBox(height: 22),
                _ProfileMenuItem(
                  icon: Icons.logout,
                  title: 'Log out',
                  subtitle: 'Log out from your account',
                  isDestructive: true,
                  onTap: () {
                    onClose();
                    showCitirideLogoutDialog(context);
                  },
                ),
                const Spacer(),
                const _DriverAppCallout(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSidebarHeader extends StatelessWidget {
  const _ProfileSidebarHeader({required this.profile, required this.onClose});

  final RiderProfile profile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB9D1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 2),
          ),
          child: Center(
            child: ClipOval(
              child: SizedBox(
                width: 58,
                height: 58,
                child: profile.photoBytes == null
                    ? const CompatibleSvgPicture.asset(
                        'assets/images/Profile.svg',
                        fit: BoxFit.contain,
                        semanticsLabel: 'Profile picture',
                      )
                    : Image.memory(profile.photoBytes!, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${profile.displayUserName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.citirideYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8D8D8D),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: onClose,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(foregroundColor: AppColors.white),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Close profile menu',
          ),
        ),
      ],
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isDestructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDestructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDestructive
        ? const Color(0xFFFF3B3B)
        : AppColors.white;
    final iconColor = isDestructive
        ? const Color(0xFFFF3B3B)
        : AppColors.citirideBlack;

    return Semantics(
      button: onTap != null,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFE9E9E9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 19),
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
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8D8D8D),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverAppCallout extends StatelessWidget {
  const _DriverAppCallout();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.citirideYellow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 8, 12, 8),
          child: Row(
            children: const [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Want to earn as a driver?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.citirideBlack,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Go to driver app',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.citirideBlack,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.citirideBlack,
                size: 27,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBottomNavigation extends StatelessWidget {
  const _HomeBottomNavigation();

  @override
  Widget build(BuildContext context) {
    return const CitirideBottomNav(activeTab: CitirideNavTab.home);
  }
}

class _HomeSearchPanel extends StatelessWidget {
  const _HomeSearchPanel({
    required this.position,
    required this.recentPlaces,
    required this.onSearchTap,
    required this.onRecentTap,
  });

  final _HomeSheetPosition position;
  final List<CitiridePlace> recentPlaces;
  final VoidCallback onSearchTap;
  final ValueChanged<CitiridePlace> onRecentTap;

  bool get _showSuggestions => position != _HomeSheetPosition.collapsed;

  @override
  Widget build(BuildContext context) {
    final visibleRecents = recentPlaces.take(3).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.citirideBlack,
        borderRadius: BorderRadius.circular(34),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 49,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4E4EA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 13),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SearchField(onTap: onSearchTap),
              ),
              if (_showSuggestions && visibleRecents.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Column(
                    children: [
                      for (var index = 0; index < visibleRecents.length; index++) ...[
                        _DestinationSuggestion(
                          iconAsset: index == 0
                              ? 'assets/images/Time_Icon.svg'
                              : 'assets/images/Location_Icon.svg',
                          title: visibleRecents[index].title,
                          subtitle: visibleRecents[index].subtitle ?? 'Nigeria',
                          onTap: () => onRecentTap(visibleRecents[index]),
                        ),
                        if (index != visibleRecents.length - 1)
                          const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.white),
          ),
          child: Row(
            children: const [
              SizedBox(width: 17),
              SizedBox(
                width: 24,
                height: 24,
                child: CompatibleSvgPicture.asset(
                  'assets/images/Search Icon.svg',
                  fit: BoxFit.contain,
                  semanticsLabel: 'Search icon',
                ),
              ),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Where are we going today?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ),
              SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationSuggestion extends StatelessWidget {
  const _DestinationSuggestion({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
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
                    fontWeight: FontWeight.w600,
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
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
