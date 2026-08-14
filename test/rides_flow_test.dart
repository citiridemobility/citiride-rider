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

  testWidgets('rides tab switches to past and opens ride details', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Rides'), findsWidgets);
    expect(find.text('Upcoming Rides'), findsOneWidget);
    expect(find.text('Lagos Street, Benin City'), findsOneWidget);

    await tester.tap(find.text('Past'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Completed'), findsNWidgets(2));
    expect(find.text('Cancelled'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ride-card-completed-lagos-ring-road-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride Completed'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Cash Payment'), findsOneWidget);
    expect(find.text('Rebook'), findsNothing);
  });

  testWidgets('upcoming ride cancel sheet can keep or cancel ride', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.bySemanticsLabel('Cancel ride'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel ride request?'), findsOneWidget);
    expect(find.text('Keep Ride'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('keep-ride-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cancel ride request?'), findsNothing);
    expect(find.text('Upcoming Rides'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Cancel ride'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-cancel-ride-button')));
    await tester.pumpAndSettle();

    expect(find.text('Select ride'), findsOneWidget);
  });
}
