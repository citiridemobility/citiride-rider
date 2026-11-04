import '../../ride/domain/live_ride.dart';

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
    this.canCancel = false,
  });

  final String id;
  final RideHistoryStatus status;
  final String dateLine;
  final String detailDate;
  final String pickup;
  final String destination;
  final String amount;
  final String paymentMethod;
  final bool canCancel;

  factory RideHistoryItem.fromLiveRide(LiveRide ride) {
    final occurredAt =
        ride.completedAt ??
        ride.cancelledAt ??
        ride.updatedAt ??
        ride.tripEndedAt ??
        ride.tripStartedAt ??
        ride.acceptedAt ??
        ride.createdAt;
    final date = occurredAt?.toDate() ?? DateTime.now();
    final fare = ride.fare.finalFare ?? ride.fare.estimated;

    return RideHistoryItem(
      id: ride.id,
      status: switch (ride.status) {
        RideStatus.completed => RideHistoryStatus.completed,
        RideStatus.cancelled => RideHistoryStatus.cancelled,
        _ => RideHistoryStatus.upcoming,
      },
      dateLine: _shortDate(date),
      detailDate: _detailDate(date),
      pickup: ride.pickup.address,
      destination: ride.destination.address,
      amount: _formatNaira(fare),
      paymentMethod: _paymentMethodLabel(ride.paymentMethod),
      canCancel: switch (ride.status) {
        RideStatus.requested ||
        RideStatus.accepted ||
        RideStatus.arriving ||
        RideStatus.waiting => true,
        _ => false,
      },
    );
  }

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

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _shortDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

String _detailDate(DateTime date) {
  final minute = date.minute.toString().padLeft(2, '0');
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${_weekdayNames[date.weekday - 1]}, ${_shortDate(date)} at '
      '$hour:$minute $period';
}

String _formatNaira(double amount) {
  final decimals = amount == amount.truncateToDouble() ? 0 : 2;
  final value = amount.toStringAsFixed(decimals);
  final parts = value.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '\u20a6$whole${parts.length == 2 ? '.${parts.last}' : ''}';
}

String _paymentMethodLabel(String method) {
  final clean = method.trim();
  if (clean.isEmpty) {
    return 'Cash';
  }
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
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
