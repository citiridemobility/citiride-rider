import 'package:citiride/features/driver/presentation/looking_for_driver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pickup notes opens chat and quick replies send automatically', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ArrivingScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('pickup-notes-field')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pickup-notes-chat-modal')),
      findsOneWidget,
    );
    expect(find.text('Type your message'), findsOneWidget);
    expect(find.text("I'm on my way"), findsOneWidget);

    await tester.tap(find.text("I'm on my way"));
    await tester.pumpAndSettle();

    expect(find.text("Hi, I'm on my way"), findsOneWidget);
    expect(find.text('Alright, coming soon'), findsOneWidget);
    expect(find.text('Hi, where are you'), findsNothing);
  });

  testWidgets('emoji is available before typing and typed messages send', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ArrivingScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('pickup-notes-field')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pickup-chat-emoji-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pickup-chat-emoji-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-chat-emoji-box')), findsOneWidget);
    expect(find.text('\u{1F600}'), findsOneWidget);
    expect(find.text('\u{1F525}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pickup-chat-emoji-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('pickup-chat-message-field')),
      'I am outside',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('pickup-chat-emoji-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pickup-chat-emoji-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-chat-emoji-box')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pickup-chat-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('I am outside'), findsOneWidget);
    expect(find.text('Alright, coming soon'), findsOneWidget);
  });
}
