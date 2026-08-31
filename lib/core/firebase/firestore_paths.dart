abstract final class FirestoreCollections {
  static const riders = 'riders';
  static const drivers = 'drivers';
  static const rides = 'rides';
  static const driverLocations = 'driverLocations';
  static const payments = 'payments';
  static const supportTickets = 'supportTickets';
}

abstract final class FirestoreFields {
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
  static const riderId = 'riderId';
  static const driverId = 'driverId';
  static const status = 'status';
  static const pickup = 'pickup';
  static const destination = 'destination';
  static const fare = 'fare';
  static const rideType = 'rideType';
  static const paymentMethod = 'paymentMethod';
}

/// Realtime Database paths (driver live location). Confirm with driver app
/// before wiring listeners — may live under Firestore instead.
abstract final class RealtimeDatabasePaths {
  static const driverLocations = 'driverLocations';
}
