enum RideHistoryStatus { upcoming, completed, cancelled }

class RideHistoryItem {
  const RideHistoryItem({
    required this.id,
    required this.status,
    required this.dateLine,
    required this.detailDate,
    required this.pickup,
    required this.destination,
    required this.amount,
    required this.paymentMethod,
  });

  final String id;
  final RideHistoryStatus status;
  final String dateLine;
  final String detailDate;
  final String pickup;
  final String destination;
  final String amount;
  final String paymentMethod;

  String get detailTitle {
    return switch (status) {
      RideHistoryStatus.upcoming => 'Upcoming Ride',
      RideHistoryStatus.completed => 'Ride Completed',
      RideHistoryStatus.cancelled => 'Ride Cancelled',
    };
  }

  String get statusLabel {
    return switch (status) {
      RideHistoryStatus.upcoming => 'Upcoming',
      RideHistoryStatus.completed => 'Completed',
      RideHistoryStatus.cancelled => 'Cancelled',
    };
  }
}

const rideHistoryItems = <RideHistoryItem>[];

RideHistoryItem? rideHistoryItemById(String? id) {
  if (id == null || id.isEmpty) {
    return null;
  }
  for (final ride in rideHistoryItems) {
    if (ride.id == id) {
      return ride;
    }
  }
  return null;
}

List<RideHistoryItem> get upcomingRideHistoryItems {
  return rideHistoryItems
      .where((ride) => ride.status == RideHistoryStatus.upcoming)
      .toList(growable: false);
}

List<RideHistoryItem> get pastRideHistoryItems {
  return rideHistoryItems
      .where((ride) => ride.status != RideHistoryStatus.upcoming)
      .toList(growable: false);
}
