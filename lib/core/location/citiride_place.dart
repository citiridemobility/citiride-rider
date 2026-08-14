import 'package:google_maps_flutter/google_maps_flutter.dart';

class CitiridePlace {
  const CitiridePlace({
    required this.title,
    this.subtitle,
    this.placeId,
    this.location,
    this.isCurrentLocation = false,
  });

  final String title;
  final String? subtitle;
  final String? placeId;
  final LatLng? location;
  final bool isCurrentLocation;

  String get displayText => title.trim().isEmpty ? 'Selected location' : title;

  CitiridePlace copyWith({
    String? title,
    String? subtitle,
    String? placeId,
    LatLng? location,
    bool? isCurrentLocation,
  }) {
    return CitiridePlace(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      placeId: placeId ?? this.placeId,
      location: location ?? this.location,
      isCurrentLocation: isCurrentLocation ?? this.isCurrentLocation,
    );
  }
}
