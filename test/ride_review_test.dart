import 'package:citiride/app/theme/app_colors.dart';
import 'package:citiride/core/location/citiride_fare.dart';
import 'package:citiride/features/review/presentation/ride_review_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GoRouter createReviewRouter(String initialLocation) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/ride-success',
          builder: (context, state) {
            return RideSuccessScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) {
            return ReviewScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(
          path: '/review-submitted',
          builder: (context, state) => const ReviewSubmittedScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const SizedBox(key: ValueKey('home-route')),
        ),
      ],
    );
  }

  FilledButton nestedButton(WidgetTester tester, String key) {
    return tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(FilledButton),
      ),
    );
  }

  testWidgets('ride success requires a rating and one suggested comment', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: createReviewRouter('/ride-success?ride=regular'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('How was your ride?'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(
      find.text(
        formatNaira(
          CitirideFareCalculator.fallback(
            CitirideRideTier.regular,
          ).estimatedTotal,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(nestedButton(tester, 'ride-success-done-button').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('ride-rating-star-5')));
    await tester.pump();

    expect(find.text('Excellent!'), findsOneWidget);
    expect(nestedButton(tester, 'ride-success-done-button').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('review-pill-Safe driving')));
    await tester.pump(const Duration(milliseconds: 180));

    final selectedPill = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byKey(const ValueKey('review-pill-Safe driving')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final selectedDecoration = selectedPill.decoration! as BoxDecoration;
    expect(selectedDecoration.color, AppColors.white);
    expect(
      nestedButton(tester, 'ride-success-done-button').onPressed,
      isNotNull,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ride-success-done-button')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review successfully submitted'), findsOneWidget);
  });

  testWidgets('additional comment opens manual review before success', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: createReviewRouter(
          '/ride-success?ride=vip&payment=wallet',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CitiRide Wallet'), findsOneWidget);
    expect(
      find.text(
        formatNaira(
          CitirideFareCalculator.fallback(CitirideRideTier.vip).estimatedTotal,
        ),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('review-pill-Any additional comment?')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('review-pill-Any additional comment?')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
    expect(
      nestedButton(tester, 'manual-review-continue-button').onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('manual-review-field')),
      'The driver was patient and helpful.',
    );
    await tester.pump();

    expect(
      nestedButton(tester, 'manual-review-continue-button').onPressed,
      isNotNull,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('manual-review-continue-button')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review successfully submitted'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review-back-home-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-route')), findsOneWidget);
  });

  testWidgets('ride success cancel skips review and goes home', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: createReviewRouter('/ride-success?ride=regular'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('ride-success-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-route')), findsOneWidget);
  });
}
