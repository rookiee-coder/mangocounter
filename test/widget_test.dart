import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangocounter/features/detection/presentation/home_screen.dart';
import 'package:mangocounter/features/detection/application/detector_provider.dart';

void main() {
  testWidgets('Demo mode banner shows when model is missing', (WidgetTester tester) async {
    // Override the provider to force demo mode state
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoModeProvider.overrideWith((ref) => true),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Initial pump and settle
    await tester.pumpAndSettle();

    expect(find.textContaining('DEMO MODE: model not found. Results are NOT real.'), findsOneWidget);
    expect(find.textContaining('DEMO MODE'), findsOneWidget);
  });
}
