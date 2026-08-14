import 'package:citiride/features/driver/presentation/cancel_ride_reason_screen.dart';
import 'package:citiride/features/driver/presentation/looking_for_driver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('arriving cancel flow requires a reason before cancelling', (
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
            );
          },
        ),
        GoRoute(
          path: '/cancel-ride-reason',
          builder: (context, state) {
            return CancelRideReasonScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
            );
          },
        ),
        GoRoute(
          path: '/select-ride',
          builder: (context, state) {
            return Text('Select ride ${state.uri.queryParameters['ride']}');
          },
        ),
        GoRoute(path: '/home', builder: (context, state) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(
      find.byKey(const ValueKey('arriving-card')),
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.drag(
      find.byKey(const ValueKey('arriving-card')),
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.byKey(const ValueKey('arriving-expanded-card')),
      findsOneWidget,
    );
    expect(find.text('Cancel ride'), findsOneWidget);

    await tester.tap(find.text('Cancel ride'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.byKey(const ValueKey('arriving-cancel-ride-sheet')),
      findsOneWidget,
    );
    expect(find.text('Are you sure?'), findsOneWidget);
    expect(find.text('Cancellation fee'), findsOneWidget);
    expect(find.text('\u20A6350'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arriving-wait-driver-button')));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure?'), findsNothing);
    expect(find.text('Arriving in 2 mins'), findsOneWidget);

    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('arriving-confirm-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('What went wrong?'), findsOneWidget);
    expect(find.text('Car not moving towards me'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('cancel-reason-submit-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Car not moving towards me'));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('cancel-reason-submit-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('cancel-reason-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Select ride vip'), findsOneWidget);
  });
}
