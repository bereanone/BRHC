import 'package:brhc_app/support/donation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('donation screen explains donation model', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DonationScreen(),
      ),
    );

    expect(find.text('Support Biblical Heritage'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.textContaining('intended to remain free'), findsOneWidget);
  });
}
