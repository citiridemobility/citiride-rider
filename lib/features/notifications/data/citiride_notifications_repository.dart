import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/auth/citiride_auth_service.dart';
import '../../../core/auth/citiride_wallet_client.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/session/citiride_session_store.dart';
import '../../ride/domain/live_ride.dart';

enum CitirideNotificationKind { ride, wallet }

/// A single account activity shown in the in-app notification inbox.
///
/// Rides are read live from Firestore and wallet entries come from the wallet
/// API, so this stays useful even if a device missed a push notification.
class CitirideNotification {
  const CitirideNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    required this.details,
    required this.occurredAt,
  });

  final String id;
  final CitirideNotificationKind kind;
  final String title;
  final String summary;
  final String details;
  final DateTime occurredAt;
}

class CitirideNotificationsRepository {
  CitirideNotificationsRepository({
    this._firestore,
    CitirideWalletClient? walletClient,
    CitirideSessionStore? sessionStore,
    CitirideAuthService? authService,
  }) : _walletClient = walletClient ?? CitirideWalletClient(),
       _sessionStore = sessionStore ?? const CitirideSessionStore(),
       _authService = authService ?? CitirideAuthService();

  final FirebaseFirestore? _firestore;
  final CitirideWalletClient _walletClient;
  final CitirideSessionStore _sessionStore;
  final CitirideAuthService _authService;

  /// Watches all activity belonging to the rider who is currently signed in.
  Stream<List<CitirideNotification>> watchCurrentRiderActivities() async* {
    final email = await _sessionStore.signedInEmail();
    final riderId = _authService.riderIdForEmail(email);
    if (riderId == null || riderId.isEmpty) {
      yield const [];
      return;
    }

    yield* watchRiderActivities(riderId: riderId);
  }

  /// Combines the rider's Firestore ride history with their wallet ledger.
  /// Wallet refreshes also recover activities created while the app was closed.
  Stream<List<CitirideNotification>> watchRiderActivities({
    required String riderId,
  }) {
    late final StreamController<List<CitirideNotification>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? ridesSubscription;
    Timer? walletRefreshTimer;
    var rides = const <LiveRide>[];
    var transactions = const <CitirideWalletTransaction>[];

    void publish() {
      if (controller.isClosed) {
        return;
      }

      final activities = <CitirideNotification>[
        for (final ride in rides) ..._rideActivities(ride),
        for (final transaction in transactions) _walletActivity(transaction),
      ]..sort((first, second) => second.occurredAt.compareTo(first.occurredAt));
      controller.add(activities);
    }

    Future<void> refreshWalletActivities() async {
      try {
        transactions = await _walletClient.fetchTransactions(limit: 50);
      } on Object {
        // Ride activity remains available when the wallet service is offline.
      }
      publish();
    }

    controller = StreamController<List<CitirideNotification>>(
      onListen: () {
        final firestore =
            _firestore ??
            (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);
        if (firestore != null) {
          ridesSubscription = firestore
              .collection(FirestoreCollections.rides)
              .where(FirestoreFields.riderId, isEqualTo: riderId)
              .snapshots()
              .listen(
                (snapshot) {
                  rides = snapshot.docs
                      .map(
                        (document) =>
                            LiveRide.fromMap(document.id, document.data()),
                      )
                      .toList(growable: false);
                  publish();
                },
                onError: (_, _) {
                  // A transient Firestore error must not hide cached wallet data.
                  publish();
                },
              );
        }
        publish();
        unawaited(refreshWalletActivities());
        walletRefreshTimer = Timer.periodic(
          const Duration(seconds: 45),
          (_) => unawaited(refreshWalletActivities()),
        );
      },
      onCancel: () async {
        walletRefreshTimer?.cancel();
        await ridesSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  static List<CitirideNotification> _rideActivities(LiveRide ride) {
    final route = _rideRoute(ride);
    final fare = _formatNaira(ride.fare.finalFare ?? ride.fare.estimated);
    final result = <CitirideNotification>[];
    final recordedKinds = <String>{};

    void add({
      required String kind,
      required Timestamp? timestamp,
      required String title,
      required String summary,
      required String details,
    }) {
      if (timestamp == null || !recordedKinds.add(kind)) {
        return;
      }
      result.add(
        CitirideNotification(
          id: 'ride-${ride.id}-$kind',
          kind: CitirideNotificationKind.ride,
          title: title,
          summary: summary,
          details: '$details\n\n$route\nFare: $fare',
          occurredAt: timestamp.toDate(),
        ),
      );
    }

    add(
      kind: 'requested',
      timestamp: ride.createdAt,
      title: 'Ride requested',
      summary: route,
      details: 'Your ${ride.rideType} ride request was sent to nearby drivers.',
    );
    add(
      kind: 'accepted',
      timestamp: ride.acceptedAt,
      title: 'Driver assigned',
      summary: ride.driverName?.isNotEmpty == true
          ? '${ride.driverName} accepted your ride'
          : 'A driver accepted your ride',
      details: 'Your driver has accepted the ride and is heading to pickup.',
    );
    add(
      kind: 'arrived',
      timestamp: ride.driverArrivedAt,
      title: 'Driver has arrived',
      summary: ride.pickup.address,
      details: 'Your driver has arrived at the pickup location.',
    );
    add(
      kind: 'started',
      timestamp: ride.tripStartedAt,
      title: 'Ride started',
      summary: 'Heading to ${ride.destination.address}',
      details: 'Your trip is now in progress.',
    );
    add(
      kind: 'fare-confirmed',
      timestamp: ride.tripEndedAt,
      title: 'Ride fare confirmed',
      summary: 'Final fare: $fare',
      details: 'Your driver has confirmed the trip fare.',
    );
    add(
      kind: 'completed',
      timestamp: ride.completedAt,
      title: 'Ride completed',
      summary: route,
      details: 'Your trip has been completed successfully.',
    );
    add(
      kind: 'cancelled',
      timestamp: ride.cancelledAt,
      title: 'Ride cancelled',
      summary: route,
      details: 'This ride was cancelled.',
    );
    add(
      kind: 'payment',
      timestamp: ride.paidAt,
      title: 'Ride payment received',
      summary: '$fare via ${ride.paymentMethod}',
      details: 'Payment for this ride was recorded as successful.',
    );

    final currentKind = switch (ride.status) {
      RideStatus.requested => 'requested',
      RideStatus.accepted || RideStatus.arriving => 'accepted',
      RideStatus.waiting => 'arrived',
      RideStatus.inProgress => 'started',
      RideStatus.confirmFare => 'fare-confirmed',
      RideStatus.completed => 'completed',
      RideStatus.cancelled => 'cancelled',
    };
    if (!recordedKinds.contains(currentKind)) {
      final title = switch (ride.status) {
        RideStatus.requested => 'Ride requested',
        RideStatus.accepted || RideStatus.arriving => 'Driver assigned',
        RideStatus.waiting => 'Driver has arrived',
        RideStatus.inProgress => 'Ride started',
        RideStatus.confirmFare => 'Ride fare confirmed',
        RideStatus.completed => 'Ride completed',
        RideStatus.cancelled => 'Ride cancelled',
      };
      add(
        kind: currentKind,
        timestamp: ride.updatedAt,
        title: title,
        summary: route,
        details: 'Latest ride update: $title.',
      );
    }

    return result;
  }

  static CitirideNotification _walletActivity(
    CitirideWalletTransaction transaction,
  ) {
    final isCredit = transaction.isCredit;
    final amount = _formatNaira(transaction.amount.abs());
    final status = transaction.status.isEmpty
        ? 'completed'
        : transaction.status.toLowerCase();
    final direction = isCredit ? 'credited to' : 'debited from';
    final provider = transaction.provider?.trim();
    final providerLine = provider == null || provider.isEmpty
        ? ''
        : '\nProvider: $provider';
    final balanceLine = transaction.balanceAfter == null
        ? ''
        : '\nBalance after: ${_formatNaira(transaction.balanceAfter!)}';
    final transactionId = transaction.id.isEmpty
        ? transaction.reference
        : transaction.id;
    return CitirideNotification(
      id: 'wallet-${transactionId.isEmpty ? transaction.createdAt?.microsecondsSinceEpoch ?? 0 : transactionId}',
      kind: CitirideNotificationKind.wallet,
      title: transaction.title,
      summary: '${isCredit ? '+' : '-'}$amount • $status',
      details:
          '$amount was $direction your CitiRide wallet.\n\n'
          'Status: $status\n'
          'Reference: ${transaction.reference.isEmpty ? 'Not available' : transaction.reference}'
          '$providerLine'
          '$balanceLine',
      occurredAt:
          transaction.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String _rideRoute(LiveRide ride) =>
      '${ride.pickup.address} → ${ride.destination.address}';

  static String _formatNaira(double amount) {
    final fixed = amount.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(?<!^)(?=(\d{3})+$)'),
      (_) => ',',
    );
    return '₦$whole.${parts.last}';
  }
}
