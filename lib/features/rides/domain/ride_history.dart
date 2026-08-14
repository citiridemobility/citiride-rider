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

const rideHistoryItems = [
  RideHistoryItem(
    id: 'upcoming-lagos-ring-road',
    status: RideHistoryStatus.upcoming,
    dateLine: 'Sun, 31 Aug 2025',
    detailDate: '31 Aug 2025',
    pickup: 'Lagos Street, Benin City',
    destination: 'Ring Road Bus Terminal, Benin City',
    amount: '\u20A61,500.00',
    paymentMethod: 'Cash Payment',
  ),
  RideHistoryItem(
    id: 'completed-lagos-ring-road-1',
    status: RideHistoryStatus.completed,
    dateLine: 'Sun, 31 Aug 2025',
    detailDate: '31 Aug 2025',
    pickup: 'Lagos Street, Benin City',
    destination: 'Ring Road Bus Terminal, Benin City',
    amount: '\u20A61,500.00',
    paymentMethod: 'Cash Payment',
  ),
  RideHistoryItem(
    id: 'cancelled-lagos-ring-road',
    status: RideHistoryStatus.cancelled,
    dateLine: 'Sun, 31 Aug 2025',
    detailDate: '31 Aug 2025',
    pickup: 'Lagos Street, Benin City',
    destination: 'Ring Road Bus Terminal, Benin City',
    amount: '\u20A61,500.00',
    paymentMethod: 'Cash Payment',
  ),
  RideHistoryItem(
    id: 'completed-lagos-ring-road-2',
    status: RideHistoryStatus.completed,
    dateLine: 'Sun, 31 Aug 2025',
    detailDate: '31 Aug 2025',
    pickup: 'Lagos Street, Benin City',
    destination: 'Ring Road Bus Terminal, Benin City',
    amount: '\u20A61,500.00',
    paymentMethod: 'Cash Payment',
  ),
];

RideHistoryItem rideHistoryItemById(String? id) {
  return rideHistoryItems.firstWhere(
    (ride) => ride.id == id,
    orElse: () => rideHistoryItems.first,
  );
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
