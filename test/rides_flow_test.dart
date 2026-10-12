import 'package:citiride/features/rides/domain/ride_history.dart';
import 'package:citiride/features/rides/presentation/ride_details_screen.dart';
import 'package:citiride/features/rides/presentation/rides_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GoRouter buildRouter({String initialLocation = '/rides'}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/rides',
          builder: (context, state) {
            return RidesScreen(
              initialTab: state.uri.queryParameters['tab'] ?? 'upcoming',
            );
          },
        ),
        GoRoute(
          path: '/ride-details',
          builder: (context, state) {
            return RideDetailsScreen(
              ride: rideHistoryItemById(state.uri.queryParameters['rideId']),
            );
          },
        ),
        GoRoute(
          path: '/select-ride',
          builder: (context, state) {
            return const Scaffold(body: Center(child: Text('Select ride')));
          },
        ),
        GoRoute(path: '/home', builder: (context, state) => const Text('Home')),
      ],
    );
  }

  testWidgets('rides tabs show empty states when there is no history', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Rides'), findsWidgets);
    expect(find.text('Upcoming Rides'), findsOneWidget);
    expect(find.text('No upcoming rides'), findsOneWidget);
    expect(find.text('Lagos Street, Benin City'), findsNothing);

    await tester.tap(find.text('Past'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No past rides'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('ride details shows empty state when ride is missing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: buildRouter(initialLocation: '/ride-details'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Ride not found'), findsOneWidget);
    expect(find.text('This trip is no longer available.'), findsOneWidget);
  });
}
