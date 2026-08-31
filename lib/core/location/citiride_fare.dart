import 'dart:math' as math;

import 'citiride_route.dart';

/// CitiRide fare rates (NGN).
///
/// Estimated trip fare uses live route distance + duration from the Routes API
/// (`CitirideRouteService`). Waiting charge applies after the free grace period
/// once the driver has arrived.
enum CitirideRideTier { regular, vip }

class CitirideFareRates {
  const CitirideFareRates({
    required this.baseFare,
    required this.perKm,
    required this.perMinute,
  });

  final double baseFare;
  final double perKm;
  final double perMinute;

  static const regular = CitirideFareRates(
    baseFare: 500,
    perKm: 120,
    perMinute: 10,
  );

  static const vip = CitirideFareRates(
    baseFare: 650,
    perKm: 145,
    perMinute: 12,
  );

  /// Free waiting minutes after driver arrival before wait billing starts.
  static const waitingGraceMinutes = 3;

  /// Waiting charge (NGN per minute) after [waitingGraceMinutes].
  static const waitingPerMinute = 10.0;

  static CitirideFareRates forTier(CitirideRideTier tier) {
    return switch (tier) {
      CitirideRideTier.regular => regular,
      CitirideRideTier.vip => vip,
    };
  }

  static CitirideRideTier tierFromRideType(String? rideType) {
    return rideType?.trim().toLowerCase() == 'vip'
        ? CitirideRideTier.vip
        : CitirideRideTier.regular;
  }
}

class CitirideFareQuote {
  const CitirideFareQuote({
    required this.tier,
    required this.distanceKm,
    required this.durationMinutes,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.estimatedTotal,
    this.waitingMinutes = 0,
    this.waitingFare = 0,
  });

  final CitirideRideTier tier;
  final double distanceKm;
  final int durationMinutes;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double estimatedTotal;
  final int waitingMinutes;
  final double waitingFare;

  double get totalWithWaiting => estimatedTotal + waitingFare;

  String get formattedEstimated => formatNaira(estimatedTotal);

  String get formattedTotalWithWaiting => formatNaira(totalWithWaiting);
}

abstract final class CitirideFareCalculator {
  /// Trip estimate from a live [CitirideRoute] (Routes API distance + duration).
  static CitirideFareQuote quote({
    required CitirideRideTier tier,
    required CitirideRoute route,
  }) {
    return quoteFromMetrics(
      tier: tier,
      distanceMeters: route.distanceMeters,
      duration: route.duration,
    );
  }

  static CitirideFareQuote quoteFromMetrics({
    required CitirideRideTier tier,
    required int distanceMeters,
    required Duration duration,
  }) {
    final rates = CitirideFareRates.forTier(tier);
    final distanceKm = math.max(0, distanceMeters) / 1000.0;
    final durationMinutes = math.max(1, (duration.inSeconds / 60).ceil());

    final distanceFare = rates.perKm * distanceKm;
    final timeFare = rates.perMinute * durationMinutes;
    final raw = rates.baseFare + distanceFare + timeFare;
    // Round up to whole naira so riders are never under-quoted.
    final estimatedTotal = raw.ceilToDouble();

    return CitirideFareQuote(
      tier: tier,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      baseFare: rates.baseFare,
      distanceFare: distanceFare,
      timeFare: timeFare,
      estimatedTotal: estimatedTotal,
    );
  }

  /// Waiting billable minutes after the free grace window.
  ///
  /// Each started minute past the grace period is charged (ceil).
  static int billableWaitingMinutes(Duration waited) {
    final overtimeSeconds =
        waited.inSeconds - CitirideFareRates.waitingGraceMinutes * 60;
    if (overtimeSeconds <= 0) {
      return 0;
    }
    return (overtimeSeconds / 60).ceil();
  }

  static double waitingFareFor(Duration waited) {
    return billableWaitingMinutes(waited) * CitirideFareRates.waitingPerMinute;
  }

  /// Apply waiting onto an existing trip quote (for final fare).
  static CitirideFareQuote withWaiting({
    required CitirideFareQuote trip,
    required Duration waited,
  }) {
    final waitingMinutes = billableWaitingMinutes(waited);
    final waitingFare = waitingMinutes * CitirideFareRates.waitingPerMinute;
    return CitirideFareQuote(
      tier: trip.tier,
      distanceKm: trip.distanceKm,
      durationMinutes: trip.durationMinutes,
      baseFare: trip.baseFare,
      distanceFare: trip.distanceFare,
      timeFare: trip.timeFare,
      estimatedTotal: trip.estimatedTotal,
      waitingMinutes: waitingMinutes,
      waitingFare: waitingFare,
    );
  }

  /// Fallback when route metrics are not ready yet.
  static CitirideFareQuote fallback(CitirideRideTier tier) {
    return quoteFromMetrics(
      tier: tier,
      distanceMeters: 5000,
      duration: const Duration(minutes: 15),
    );
  }
}

String formatNaira(num amount, {bool withSymbol = true}) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  final signed = rounded < 0 ? '-${buffer.toString()}' : buffer.toString();
  return withSymbol ? '\u20A6$signed' : signed;
}

/// Display helper for ride cards while the route is loading.
String fareLabelForRoute({
  required CitirideRideTier tier,
  required CitirideRoute? route,
  required bool isLoadingRoute,
}) {
  if (isLoadingRoute) {
    return 'Calculating…';
  }
  if (route == null) {
    return '—';
  }
  return CitirideFareCalculator.quote(tier: tier, route: route).formattedEstimated;
}

double? parseEstimatedFareQuery(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return double.tryParse(value.trim());
}
