import 'package:citiride/features/driver/presentation/looking_for_driver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  tearDown(() {
    debugShareRideLauncher = null;
  });

  testWidgets('arriving share ride opens native share with ride details', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ShareParams? sharedParams;
    debugShareRideLauncher = (params) async {
      sharedParams = params;
    };

    final router = GoRouter(
      initialLocation: '/arriving?ride=vip',
      routes: [
        GoRoute(
          path: '/arriving',
          builder: (context, state) {
            return ArrivingScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Lagos Street',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
            );
          },
        ),
        GoRoute(path: '/home', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/cancel-ride-reason',
          builder: (context, state) => const SizedBox(),
        ),
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

    await tester.tap(find.text('Share ride details'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('share-ride-details-sheet')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Share ride screenshot'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-ride-button')));
    await tester.pumpAndSettle();

    expect(sharedParams?.text, contains('CitiRide trip'));
    expect(sharedParams?.text, contains('Driver'));
    expect(sharedParams?.text, contains('Lagos Street'));
    expect(sharedParams?.text, contains('Ring Road Bus Terminal'));
    expect(sharedParams?.files?.length, 1);
    expect(sharedParams?.fileNameOverrides, ['citiride-ride-details.svg']);
  });

  testWidgets('ride arrival share ride uses native share payload', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ShareParams? sharedParams;
    debugShareRideLauncher = (params) async {
      sharedParams = params;
    };

    await tester.pumpWidget(const MaterialApp(home: RideArrivalScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Share ride details'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('share-ride-details-sheet')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Share ride screenshot'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share-ride-button')));
    await tester.pumpAndSettle();

    expect(sharedParams?.text, contains('CitiRide trip'));
    expect(sharedParams?.text, contains('Lagos Street'));
    expect(sharedParams?.text, contains('Ring Road Bus Terminal'));
    expect(sharedParams?.files?.length, 1);
    expect(sharedParams?.fileNameOverrides, ['citiride-ride-details.svg']);
  });
}
