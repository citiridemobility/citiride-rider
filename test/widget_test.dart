import 'package:citiride/app/citiride_app.dart';
import 'package:citiride/core/firebase/firebase_bootstrap.dart';
import 'package:citiride/features/driver/presentation/looking_for_driver_screen.dart';
import 'package:citiride/features/home/presentation/home_screen.dart';
import 'package:citiride/features/profile/domain/rider_profile.dart';
import 'package:citiride/features/settings/presentation/settings_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const recentHistoryJson =
      '[{"title":"Benin City","subtitle":"Nigeria","lat":6.335,"lng":5.6037},{"title":"Afemai Transport Company","subtitle":"Dawson Road, Benin City","lat":6.3339,"lng":5.6252},{"title":"Ring Road Bus Terminal","subtitle":"Oba Market Road, Benin City 300102","lat":6.3374,"lng":5.6149}]';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'citiride.location_search_history': recentHistoryJson,
    });
  });
  Future<void> pumpToOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      CitirideApp(
        firebaseStatus: const FirebaseStatus.unconfigured('Test config'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('CitiRide'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Onboarding slide 1 artwork'), findsOneWidget);
    expect(find.bySemanticsLabel('Clock icon'), findsOneWidget);
  }

  Future<void> expectWelcomeScreen(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Sign up or Log in to continue'), findsOneWidget);
    expect(find.bySemanticsLabel('Welcome artwork'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  }

  Future<void> pumpToWelcome(WidgetTester tester) async {
    await pumpToOnboarding(tester);
    await tester.tap(find.text('Skip'));
    await expectWelcomeScreen(tester);
  }

  Future<void> pumpToEnterNumber(WidgetTester tester) async {
    await pumpToWelcome(tester);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email-field')), findsOneWidget);
    expect(find.bySemanticsLabel('Nigeria country code'), findsNothing);
    expect(find.text('Use phone number instead'), findsNothing);
  }

  Future<void> tapDialDigits(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.byKey(ValueKey('dial-key-$digit')));
      await tester.pump();
    }
  }

  Future<void> pumpToEnterCode(WidgetTester tester) async {
    await pumpToEnterNumber(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'rider@example.com',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('rider@example.com'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('verification-code-box-5')),
      findsOneWidget,
    );
  }

  Future<void> pumpToSetLocation(WidgetTester tester) async {
    await pumpToEnterCode(tester);

    await tapDialDigits(tester, '968999');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();

    expect(find.text('Set your location?'), findsOneWidget);
    expect(find.text('Set location'), findsOneWidget);
    expect(find.text('Do it later'), findsOneWidget);
  }

  FilledButton continueButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue').last,
    );
  }

  Future<void> pumpHomeFrame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('citiride routes from splash to onboarding', (
    WidgetTester tester,
  ) async {
    await pumpToOnboarding(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('next and continue route from onboarding to welcome', (
    WidgetTester tester,
  ) async {
    await pumpToOnboarding(tester);

    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Onboarding slide 2 artwork'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Onboarding slide 3 artwork'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await expectWelcomeScreen(tester);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('skip routes from onboarding to welcome', (
    WidgetTester tester,
  ) async {
    await pumpToOnboarding(tester);

    await tester.tap(find.text('Skip'));
    await expectWelcomeScreen(tester);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sign up routes from welcome to enter email', (
    WidgetTester tester,
  ) async {
    await pumpToEnterNumber(tester);

    expect(continueButton(tester).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid email address shows error and disables continue', (
    WidgetTester tester,
  ) async {
    await pumpToEnterNumber(tester);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'not-an-email',
    );
    await tester.pump();

    expect(find.text('Invalid email address'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('valid email address enables continue', (
    WidgetTester tester,
  ) async {
    await pumpToEnterNumber(tester);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'rider@example.com',
    );
    await tester.pump();

    expect(find.text('Invalid email address'), findsNothing);
    expect(continueButton(tester).onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('valid email auth can continue into code screen', (
    WidgetTester tester,
  ) async {
    await pumpToEnterNumber(tester);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'rider@example.com',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Enter the code'), findsOneWidget);
    expect(
      find.text('A one-time password was sent to your email'),
      findsOneWidget,
    );
    expect(find.text('rider@example.com'), findsAtLeastNWidgets(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('valid email continue routes to enter code screen', (
    WidgetTester tester,
  ) async {
    await pumpToEnterCode(tester);

    expect(find.text('Resend code in 40'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resend code countdown reaches resend state', (
    WidgetTester tester,
  ) async {
    await pumpToEnterCode(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code in 39'), findsOneWidget);

    await tester.pump(const Duration(seconds: 39));
    expect(find.text('Resend code'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incorrect verification code shows error state', (
    WidgetTester tester,
  ) async {
    await pumpToEnterCode(tester);

    await tapDialDigits(tester, '968990');
    expect(continueButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    expect(find.text('Incorrect code'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('correct verification code shows success flow and set location', (
    WidgetTester tester,
  ) async {
    await pumpToEnterCode(tester);

    await tapDialDigits(tester, '968999');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    expect(find.text('Please wait'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('verification-code-correct')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Sign up successful'), findsOneWidget);
    expect(find.text('Proceed'), findsOneWidget);

    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();

    expect(find.text('Set your location?'), findsOneWidget);
    expect(find.text('Set location'), findsOneWidget);
    expect(find.text('Do it later'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('set-location-map-background')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('do it later routes to home immediately', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    expect(find.byKey(const ValueKey('home-map-background')), findsOneWidget);
    expect(find.text('Where are we going today?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('set location permission success routes to home', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('citiride/location_permission'),
          (_) async => true,
        );
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Set location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(find.byKey(const ValueKey('home-map-background')), findsOneWidget);
    expect(find.text('Where are we going today?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('passcode success sheet returns to security screen', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/security',
      routes: [
        GoRoute(
          path: '/security',
          builder: (context, state) => const SecurityScreen(),
        ),
        GoRoute(
          path: '/change-passcode',
          builder: (context, state) => const ChangePasscodeScreen(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/change-passcode');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('old-passcode-field')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-passcode-field')),
      '654321',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('change-passcode-save-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Passcode changed successfully'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Change Wallet Passcode'), findsOneWidget);
  });

  testWidgets('transaction pin success sheet returns to security screen', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/security',
      routes: [
        GoRoute(
          path: '/security',
          builder: (context, state) => const SecurityScreen(),
        ),
        GoRoute(
          path: '/reset-pin-new',
          builder: (context, state) => const ResetPinNewPinScreen(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/reset-pin-new');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('new-transaction-pin-field')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-transaction-pin-field')),
      '123456',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('reset-pin-new-save-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Transaction PIN reset successfully'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Reset Transaction PIN'), findsOneWidget);
  });

  testWidgets('personal info updates profile details and returns to sidebar', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);
    await tester.tap(find.byKey(const ValueKey('home-profile-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal info'));
    await tester.pumpAndSettle();

    expect(find.text('Personal info'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-save-button')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('profile-save-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('profile-name-field')),
      'Ada Osigbemhe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-username-field')),
      'ada_fav',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-phone-field')),
      '8031234567',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('profile-save-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('profile-save-button')));
    await tester.pump();

    expect(find.text('Please wait'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Profile updated successfully'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Osigbemhe'), findsOneWidget);
    expect(find.text('@ada_fav'), findsOneWidget);
    expect(find.text('+234 803 1234 567'), findsOneWidget);
    expect(find.text('Edit profile info'), findsOneWidget);

    await tester.tap(find.text('Edit profile info'));
    await tester.pumpAndSettle();

    expect(find.text('Enter username'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('profile-name-field')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Ada Osigbemhe',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('profile-username-field')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'ada_fav',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-phone-field')))
          .controller!
          .text,
      '8031234567',
    );

    RiderProfileStore.instance.update(
      const RiderProfile(
        fullName: 'Osigbemhe',
        userName: 'osi_fav',
        phoneNumber: '+234 902 2829 192',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('profile icon opens and closes profile sidebar', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    expect(find.text('Personal info'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('Osigbemhe'), findsOneWidget);
    expect(find.text('Personal info'), findsOneWidget);
    expect(find.text('Want to earn as a driver?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-sidebar-scrim')));
    await tester.pumpAndSettle();

    expect(find.text('Personal info'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('home search routes to editable route screen', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    await tester.tap(find.text('Where are we going today?'));
    await tester.pumpAndSettle();

    expect(find.text('Your Route'), findsOneWidget);
    expect(find.bySemanticsLabel('Add stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Switch route'), findsOneWidget);
    expect(find.bySemanticsLabel('Open map'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-location-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('route-destination-field')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Request a ride'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request a ride'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.bySemanticsLabel('Add stop'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-stop-field')), findsOneWidget);
    expect(find.text('Add a stop'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add stop'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-stop-field')), findsNothing);
    expect(find.text('Add a stop'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Add stop'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-stop-field')), findsOneWidget);
    expect(find.text('Add a stop'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Airport Road',
    );
    await tester.pump();

    expect(find.text('Airport Road'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request a ride'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.bySemanticsLabel('Switch route'));
    await tester.pumpAndSettle();

    expect(find.text('Airport Road'), findsWidgets);
    expect(find.text('Current Location'), findsOneWidget);

    final locationField = tester.widget<TextField>(
      find.byKey(const ValueKey('route-location-field')),
    );
    final destinationField = tester.widget<TextField>(
      find.byKey(const ValueKey('route-destination-field')),
    );

    expect(locationField.controller?.text, 'Airport Road');
    expect(destinationField.controller?.text, 'Current Location');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('request a ride routes to select ride and pickup screens', (
    WidgetTester tester,
  ) async {
    Future<void> advanceAnimatedFlow() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    await tester.tap(find.text('Where are we going today?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Ring Road Bus Terminal',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Request a ride'));
    await tester.pumpAndSettle();

    expect(find.text('Select payment Options'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.text('\u20A63,500'), findsOneWidget);
    expect(find.bySemanticsLabel('Ride route direction'), findsOneWidget);
    expect(find.bySemanticsLabel('Cash payment'), findsOneWidget);

    await tester.tap(find.text('VIP'));
    await tester.pumpAndSettle();

    expect(find.text('Select payment Options'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Select pickup location'), findsOneWidget);
    expect(find.text('Current Location'), findsWidgets);
    expect(find.text('Modern Car Models'), findsOneWidget);
    expect(find.text('\u20A67,500'), findsOneWidget);
    expect(find.text('Confirm Order'), findsOneWidget);
    expect(find.bySemanticsLabel('Pickup route direction'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Order'));
    await advanceAnimatedFlow();

    expect(find.text('Looking for Driver'), findsOneWidget);
    expect(find.text('Looking for a driver nearby'), findsOneWidget);
    expect(find.bySemanticsLabel('Looking route direction'), findsOneWidget);
    expect(find.bySemanticsLabel('Searching vehicle'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit pickup'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancel ride'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('looking-action-edit-pickup')));
    await advanceAnimatedFlow();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsOneWidget);
    expect(find.text('My Location'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pickup-result-benin city')));
    await advanceAnimatedFlow();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsNothing);
    expect(find.text('Looking for Driver'), findsOneWidget);
    expect(find.text('Benin City'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await advanceAnimatedFlow();

    expect(find.text('Looking for Driver'), findsNothing);
    expect(find.text('Driver found'), findsOneWidget);
    expect(find.bySemanticsLabel('Driver found map cars'), findsOneWidget);
    expect(
      find.text('Waiting for driver to confirm the order'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Driver profile'), findsOneWidget);
    expect(find.text('My route'), findsOneWidget);
    expect(find.text('Benin City'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('driver-found-card')),
      const Offset(0, -360),
    );
    await advanceAnimatedFlow();

    expect(
      find.byKey(const ValueKey('driver-found-expanded-card')),
      findsOneWidget,
    );
    expect(find.text('Andrew Johnson'), findsOneWidget);
    expect(find.textContaining('Green', findRichText: true), findsOneWidget);
    expect(find.text('BEN931AP'), findsOneWidget);
    expect(find.text('Any pickup notes?'), findsOneWidget);
    expect(find.bySemanticsLabel('Call driver'), findsOneWidget);
    expect(find.text('Add stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Add stop icon'), findsOneWidget);
    expect(find.bySemanticsLabel('Destination location icon'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit pickup location'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit destination'), findsOneWidget);
    expect(find.text('Edit Destinations'), findsOneWidget);
    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.bySemanticsLabel('Cash payment icon'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('\u20A63,500'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Edit pickup location'));
    await advanceAnimatedFlow();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('pickup-search-field')))
          .controller
          ?.text,
      'Benin City',
    );

    await tester.tap(find.text('Afemai Transport Company'));
    await advanceAnimatedFlow();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsNothing);
    expect(find.text('Driver found'), findsOneWidget);
    expect(find.text('Afemai Transport Company'), findsWidgets);

    await tester.tap(find.text('Edit Destinations'));
    await advanceAnimatedFlow();

    expect(find.text('Your Route'), findsOneWidget);
    expect(find.text('Request a ride'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('route-location-field')))
          .controller
          ?.text,
      'Afemai Transport Company',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('route-destination-field')),
          )
          .controller
          ?.text,
      'Ring Road Bus Terminal',
    );

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Airport Road',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await advanceAnimatedFlow();

    expect(find.text('Driver found'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('driver-found-expanded-card')),
      findsOneWidget,
    );
    expect(find.text('Airport Road'), findsWidgets);
    expect(
      find.text(
        'Price will change after the ride ends since destination has been changed.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('driver-found-sheet-handle')));
    await advanceAnimatedFlow();

    expect(
      find.byKey(const ValueKey('driver-found-collapsed-card')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('looking-action-cancel-ride')));
    await advanceAnimatedFlow();

    expect(find.text('Cancel ride request?'), findsOneWidget);
    expect(find.text('Keep Ride'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('confirm-cancel-ride-button')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Keep Ride'));
    await advanceAnimatedFlow();

    expect(find.text('Cancel ride request?'), findsNothing);
    expect(find.text('Driver found'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('looking-action-cancel-ride')));
    await advanceAnimatedFlow();
    await tester.tap(find.byKey(const ValueKey('confirm-cancel-ride-button')));
    await advanceAnimatedFlow();

    expect(find.text('Select payment Options'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cash payment option opens payment options screen', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    await tester.tap(find.text('Where are we going today?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Ring Road Bus Terminal',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Request a ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('VIP'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('select-ride-payment-option')));
    await tester.pumpAndSettle();

    expect(find.text('Payment Options'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('CitiRide Wallet'), findsOneWidget);
    expect(find.text('Bal: \u20A63,000'), findsOneWidget);
    expect(find.bySemanticsLabel('Payment route direction'), findsOneWidget);

    final vipCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('payment-ride-card-container-vip')),
    );
    final vipDecoration = vipCard.decoration! as BoxDecoration;
    final vipBorder = vipDecoration.border! as Border;
    expect(vipBorder.top.color, const Color(0xFFF5E700));

    await tester.tap(find.byKey(const ValueKey('payment-method-wallet')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Select payment Options'), findsOneWidget);
    expect(find.text('CitiRide Wallet'), findsOneWidget);
    expect(find.text('Bal: \u20A63,000'), findsOneWidget);
    expect(find.bySemanticsLabel('CitiRide Wallet payment'), findsOneWidget);

    final returnedVipCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ride-card-container-vip')),
    );
    final returnedVipDecoration = returnedVipCard.decoration! as BoxDecoration;
    final returnedVipBorder = returnedVipDecoration.border! as Border;
    expect(returnedVipBorder.top.color, const Color(0xFFF5E700));

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Select pickup location'), findsOneWidget);
    expect(find.text('Modern Car Models'), findsOneWidget);
    expect(find.text('\u20A67,500'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pickup search modal updates pickup location', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    await tester.tap(find.text('Where are we going today?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Ring Road Bus Terminal',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Request a ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regular'));
    await tester.pumpAndSettle();

    expect(find.text('Select payment Options'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pickup-search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('pickup-search-field')))
          .controller
          ?.text,
      'Current Location',
    );
    expect(find.text('My Location'), findsOneWidget);
    expect(find.text('Benin City'), findsWidgets);
    expect(find.text('Afemai Transport Company'), findsOneWidget);
    expect(find.text('Ring Road Bus Terminal'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('pickup-search-field')),
      'Airport Road',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsNothing);
    expect(find.text('Airport Road'), findsWidgets);
    expect(find.text('Select pickup location'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pickup-search-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pickup-result-benin city')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-search-field')), findsNothing);
    expect(find.text('Benin City'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('select ride route controls open route editor', (
    WidgetTester tester,
  ) async {
    await pumpToSetLocation(tester);

    await tester.tap(find.text('Do it later'));
    await pumpHomeFrame(tester);

    await tester.tap(find.text('Where are we going today?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('route-destination-field')),
      'Ring Road Bus Terminal',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Request a ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('select-ride-route-summary')));
    await tester.pumpAndSettle();

    expect(find.text('Your Route'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('route-destination-field')),
          )
          .controller
          ?.text,
      'Ring Road Bus Terminal',
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('select-ride-add-stop')));
    await tester.pumpAndSettle();

    expect(find.text('Your Route'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-stop-field')), findsOneWidget);
    expect(find.text('Add a stop'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('route-destination-field')),
          )
          .controller
          ?.text,
      'Ring Road Bus Terminal',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home search sheet expands through swipe states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await pumpHomeFrame(tester);

    await tester.dragFrom(
      tester
          .getRect(find.byKey(const ValueKey('home-search-sheet-collapsed')))
          .center,
      const Offset(0, -280),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey('home-search-sheet-preview')),
      findsOneWidget,
    );
    expect(find.text('Benin City'), findsWidgets);
    expect(find.text('Afemai Transport Company'), findsOneWidget);
    expect(find.text('Ring Road Bus Terminal'), findsWidgets);

    await tester.dragFrom(
      tester
          .getRect(find.byKey(const ValueKey('home-search-sheet-preview')))
          .center,
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey('home-search-sheet-expanded')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('driver found confirms and routes to arriving screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/driver-found',
      routes: [
        GoRoute(
          path: '/driver-found',
          builder: (context, state) {
            return DriverFoundScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'vip',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Lagos Street',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
            );
          },
        ),
        GoRoute(
          path: '/arriving',
          builder: (context, state) {
            return ArrivingScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'vip',
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
          path: '/select-ride',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Driver found'), findsOneWidget);
    expect(find.bySemanticsLabel('Driver found map cars'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Driver found'), findsNothing);
    expect(find.text('Arriving in 2 mins'), findsOneWidget);
    expect(find.bySemanticsLabel('Arriving map image'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('arriving-collapsed-card')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('arriving-collapsed-card')),
        matching: find.text('Lagos Street'),
      ),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('arriving-card')),
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('arriving-preview-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('arriving-expanded-card')), findsNothing);
    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.text('More'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('arriving-card')),
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.byKey(const ValueKey('arriving-expanded-card')),
      findsOneWidget,
    );
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Share ride details'), findsOneWidget);
    expect(find.text('Contact driver'), findsOneWidget);
    expect(find.text('Cancel ride'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
