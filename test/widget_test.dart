import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:langgry/features/auth/splash/presentation/splash_screen/splash_screen.dart';

void main() {
  testWidgets('shows the LANGGRY splash brand', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(onFinished: () {}),
      ),
    );
    expect(find.text('LANGGRY'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
  });
}
