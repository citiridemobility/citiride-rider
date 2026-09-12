import 'package:citiride/core/location/citiride_fare.dart';
import 'package:citiride/features/driver/presentation/looking_for_driver_screen.dart';
import 'package:citiride/features/review/presentation/ride_review_screens.dart';
import 'package:citiride/features/ride/domain/live_ride.dart';
import 'package:citiride/features/ride/presentation/ride_trip_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('ended trips go to payment until the rider pays, then review', () {
    expect(
      routePathForRideStatus(RideStatus.confirmFare),
      '/ride-payment',
    );
    expect(
      routePathForRideStatus(RideStatus.confirmFare, paymentPaid: true),
      '/ride-success',
    );
    expect(routePathForRideStatus(RideStatus.completed), '/ride-success');
    expect(
      routePathForRideStatus(RideStatus.inProgress),
      '/driving-to-destination',
    );
  });
  testWidgets('arriving routes to ride arrival then driving to destination', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/arriving?ride=vip',
      routes: [
        GoRoute(
          path: '/arriving',
          builder: (context, state) {
            return ArrivingScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Lagos Street',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
            );
          },
        ),
        GoRoute(
          path: '/ride-arrival',
          builder: (context, state) {
            return RideArrivalScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Lagos Street',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
            );
          },
        ),
        GoRoute(
          path: '/driving-to-destination',
          builder: (context, state) {
            return DrivingToDestinationScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Lagos Street',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              autoCompleteTrip: true,
            );
          },
        ),
        GoRoute(
          path: '/ride-success',
          builder: (context, state) {
            return RideSuccessScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(path: '/home', builder: (context, state) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Driver is on the way'), findsOneWidget);
    expect(find.text('Arriving In 2 mins'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Your ride has arrived'), findsOneWidget);
    expect(find.bySemanticsLabel('Ride arrival map image'), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-arrival-card')), findsOneWidget);
    expect(find.textContaining('Free wait time'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Driving to destination'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Driving to destination map image'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('driving-to-destination-card')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('How was your ride?'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(
      find.text(
        formatNaira(
          CitirideFareCalculator.fallback(CitirideRideTier.vip).estimatedTotal,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('ride arrival waiting countdown shows fee after free wait ends', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: RideArrivalScreen(autoStartTrip: false)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Free wait time 03:00'), findsOneWidget);

    await tester.pump(const Duration(minutes: 3));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Waiting fee'), findsOneWidget);
  });
}
