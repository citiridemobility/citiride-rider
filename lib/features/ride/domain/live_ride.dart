import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/location/citiride_fare.dart';
import '../../../core/location/citiride_route.dart';

Map<String, dynamic>? asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

Timestamp? timestampFrom(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value;
  }
  if (value is DateTime) {
    return Timestamp.fromDate(value);
  }
  if (value is num) {
    final raw = value.toInt();
    if (raw <= 0) {
      return null;
    }
    // Driver writes Date.now() milliseconds; some paths use seconds.
    final millis = raw < 1000000000000 ? raw * 1000 : raw;
    return Timestamp.fromMillisecondsSinceEpoch(millis);
  }
  return null;
}

enum RideStatus {
  requested,
  accepted,
  arriving,
  waiting,
  inProgress,
  confirmFare,
  completed,
  cancelled;

  String toFirestore() {
    return switch (this) {
      RideStatus.requested => 'requested',
      RideStatus.accepted => 'accepted',
      RideStatus.arriving => 'arriving',
      RideStatus.waiting => 'waiting',
      RideStatus.inProgress => 'in_progress',
      RideStatus.confirmFare => 'confirm_fare',
      RideStatus.completed => 'completed',
      RideStatus.cancelled => 'cancelled',
    };
  }

  static RideStatus fromFirestore(String? value) {
    return switch (value) {
      'requested' => RideStatus.requested,
      'accepted' => RideStatus.accepted,
      'arriving' => RideStatus.arriving,
      'waiting' => RideStatus.waiting,
      'in_progress' => RideStatus.inProgress,
      'confirm_fare' => RideStatus.confirmFare,
      'completed' => RideStatus.completed,
      'cancelled' => RideStatus.cancelled,
      _ => RideStatus.requested,
    };
  }

  bool get isTerminal =>
      this == RideStatus.completed || this == RideStatus.cancelled;

  bool get hasDriverAssigned =>
      this == RideStatus.accepted ||
      this == RideStatus.arriving ||
      this == RideStatus.waiting ||
      this == RideStatus.inProgress ||
      this == RideStatus.confirmFare;
}

class RideLatLng {
  const RideLatLng({
    required this.lat,
    required this.lng,
    required this.address,
  });

  final double lat;
  final double lng;
  final String address;

  Map<String, Object?> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'address': address,
      // Driver matching / Cloud Functions / map UI use these keys.
      'latitude': lat,
      'longitude': lng,
      'name': address,
    };
  }

  factory RideLatLng.fromMap(Map<String, dynamic>? map, {String fallback = ''}) {
    final address = (map?['address'] as String?)?.trim();
    final name = (map?['name'] as String?)?.trim();
    return RideLatLng(
      lat:
          (map?['lat'] as num?)?.toDouble() ??
          (map?['latitude'] as num?)?.toDouble() ??
          0,
      lng:
          (map?['lng'] as num?)?.toDouble() ??
          (map?['longitude'] as num?)?.toDouble() ??
          0,
      address: (address != null && address.isNotEmpty)
          ? address
          : (name != null && name.isNotEmpty)
          ? name
          : fallback,
    );
  }
}

class RideFare {
  const RideFare({required this.estimated, this.finalFare});

  final double estimated;
  final double? finalFare;

  Map<String, Object?> toMap() {
    return {'estimated': estimated, 'final': finalFare};
  }

  factory RideFare.fromMap(Map<String, dynamic>? map) {
    return RideFare(
      estimated: (map?['estimated'] as num?)?.toDouble() ?? 0,
      finalFare: (map?['final'] as num?)?.toDouble(),
    );
  }
}

class LiveRide {
  const LiveRide({
    required this.id,
    required this.riderId,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.fare,
    this.driverId,
    this.driverLocation,
    this.driverName,
    this.driverImage,
    this.driverVehicle,
    this.driverPlate,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
    this.createdAt,
    this.updatedAt,
    this.lastDeclinedAt,
  });

  final String id;
  final String riderId;
  final String? driverId;
  final RideStatus status;
  final RideLatLng pickup;
  final RideLatLng destination;
  final RideFare fare;
  final DriverLocation? driverLocation;
  final String? driverName;
  final String? driverImage;
  final String? driverVehicle;
  final String? driverPlate;
  final String rideType;
  final String paymentMethod;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final Timestamp? lastDeclinedAt;

  factory LiveRide.fromMap(String id, Map<String, dynamic> data) {
    final rawDriverLocation = data['driverLocation'];
    return LiveRide(
      id: id,
      riderId: (data['riderId'] as String?)?.trim() ?? '',
      driverId: (data['driverId'] as String?)?.trim(),
      status: RideStatus.fromFirestore(data['status'] as String?),
      pickup: RideLatLng.fromMap(
        asStringKeyedMap(data['pickup']),
        fallback: 'Pickup',
      ),
      destination: RideLatLng.fromMap(
        asStringKeyedMap(data['destination']),
        fallback: 'Destination',
      ),
      fare: RideFare.fromMap(asStringKeyedMap(data['fare'])),
      driverLocation: rawDriverLocation is Map
          ? DriverLocation.fromMap(rawDriverLocation)
          : null,
      driverName: (data['driverName'] as String?)?.trim(),
      driverImage: (data['driverImage'] as String?)?.trim(),
      driverVehicle: (data['driverVehicle'] as String?)?.trim(),
      driverPlate: (data['driverPlate'] as String?)?.trim(),
      rideType: (data['rideType'] as String?)?.trim().isNotEmpty == true
          ? (data['rideType'] as String).trim()
          : 'regular',
      paymentMethod:
          (data['paymentMethod'] as String?)?.trim().isNotEmpty == true
          ? (data['paymentMethod'] as String).trim()
          : 'cash',
      createdAt: timestampFrom(data['createdAt']),
      updatedAt: timestampFrom(data['updatedAt']),
      lastDeclinedAt: timestampFrom(data['lastDeclinedAt']),
    );
  }
}

class DriverLocation {
  const DriverLocation({
    required this.lat,
    required this.lng,
    required this.heading,
    this.updatedAt,
  });

  final double lat;
  final double lng;
  final double heading;
  final Timestamp? updatedAt;

  factory DriverLocation.fromMap(Map<dynamic, dynamic> data) {
    return DriverLocation(
      lat:
          (data['lat'] as num?)?.toDouble() ??
          (data['latitude'] as num?)?.toDouble() ??
          0,
      lng:
          (data['lng'] as num?)?.toDouble() ??
          (data['longitude'] as num?)?.toDouble() ??
          0,
      heading: (data['heading'] as num?)?.toDouble() ?? 0,
      updatedAt: timestampFrom(data['updatedAt']),
    );
  }
}

/// A nearby online driver for map display.
class NearbyDriver {
  const NearbyDriver({
    required this.driverId,
    required this.lat,
    required this.lng,
    this.heading = 0,
  });

  final String driverId;
  final double lat;
  final double lng;
  final double heading;

  factory NearbyDriver.fromMap(String id, Map<String, dynamic> data) {
    return NearbyDriver(
      driverId: id,
      lat:
          (data['lat'] as num?)?.toDouble() ??
          (data['latitude'] as num?)?.toDouble() ??
          0,
      lng:
          (data['lng'] as num?)?.toDouble() ??
          (data['longitude'] as num?)?.toDouble() ??
          0,
      heading: (data['heading'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Public driver card fields from `drivers/{driverId}`.
class DriverProfileSummary {
  const DriverProfileSummary({
    required this.driverId,
    this.displayName,
    this.photoUri,
    this.vehicleLabel,
    this.plateNumber,
  });

  final String driverId;
  final String? displayName;
  final String? photoUri;
  final String? vehicleLabel;
  final String? plateNumber;

  factory DriverProfileSummary.fromMap(String id, Map<String, dynamic> data) {
    final vehicleDetails = asStringKeyedMap(data['vehicleDetails']);
    final personalInfo = asStringKeyedMap(data['personalInfo']);

    String? firstNonEmpty(List<String?> values) {
      for (final value in values) {
        final clean = value?.trim();
        if (clean != null && clean.isNotEmpty) {
          return clean;
        }
      }
      return null;
    }

    return DriverProfileSummary(
      driverId: id,
      displayName: firstNonEmpty([
        data['displayName'] as String?,
        data['name'] as String?,
        personalInfo?['fullName'] as String?,
        personalInfo?['name'] as String?,
      ]),
      photoUri: firstNonEmpty([
        data['photoUri'] as String?,
        data['photoURL'] as String?,
        data['profilePhoto'] as String?,
        personalInfo?['photoUri'] as String?,
      ]),
      vehicleLabel: firstNonEmpty([
        data['vehicleMakeModel'] as String?,
        data['vehicleModel'] as String?,
        vehicleDetails?['vehicleMakeModel'] as String?,
        data['vehicle'] as String?,
      ]),
      plateNumber: firstNonEmpty([
        data['vehiclePlateNumber'] as String?,
        data['vehiclePlate'] as String?,
        vehicleDetails?['vehiclePlateNumber'] as String?,
        data['plateNumber'] as String?,
      ]),
    );
  }
}

/// Payload for creating a new ride request (rider → Firestore).
class NewRideRequest {
  const NewRideRequest({
    required this.riderId,
    required this.pickup,
    required this.destination,
    required this.estimatedFare,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
    this.riderName = 'Rider',
    this.riderImage,
  });

  final String riderId;
  final RideLatLng pickup;
  final RideLatLng destination;
  final double estimatedFare;
  final String rideType;
  final String paymentMethod;
  final String riderName;
  final String? riderImage;
}

/// Write map for a new ride. Always stamps server timestamps.
Map<String, Object?> newRideWriteMap(NewRideRequest request) {
  return {
    'riderId': request.riderId,
    'driverId': null,
    'status': RideStatus.requested.toFirestore(),
    'pickup': request.pickup.toMap(),
    'destination': request.destination.toMap(),
    'fare': {'estimated': request.estimatedFare, 'final': null},
    'rideType': request.rideType,
    'paymentMethod': request.paymentMethod,
    'riderName': request.riderName,
    if (request.riderImage != null) 'riderImage': request.riderImage,
    'riderRating': '5.0',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Map<String, Object?> rideStatusUpdateMap(RideStatus status, {String? driverId}) {
  return {
    'status': status.toFirestore(),
    'driverId': ?driverId,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Same rider document id scheme used by [CitirideAuthService] (`riders/{id}`).
String riderIdFromEmail(String email) {
  return email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9@._+-]'), '_');
}

double estimatedFareForRideType(String rideType, {CitirideRoute? route}) {
  final tier = CitirideFareRates.tierFromRideType(rideType);
  if (route != null) {
    return CitirideFareCalculator.quote(tier: tier, route: route).estimatedTotal;
  }
  return CitirideFareCalculator.fallback(tier).estimatedTotal;
}
