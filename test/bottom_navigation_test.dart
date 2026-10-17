import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/presentation/app_shell.dart';

void main() {
  testWidgets('bottom navigation exposes all work areas and the scan action',
      (tester) async {
    var destination = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: OrchardBottomNavigation(
            selectedIndex: 0,
            onDashboard: () => destination = 'dashboard',
            onHarvest: () => destination = 'harvest',
            onScan: () => destination = 'scan',
            onHistory: () => destination = 'history',
            onAssistant: () => destination = 'assistant',
          ),
        ),
      ),
    );

    expect(find.byTooltip('Dashboard'), findsOneWidget);
    expect(find.byTooltip('Harvest plan'), findsOneWidget);
    expect(find.byTooltip('History'), findsOneWidget);
    expect(find.byTooltip('AI assistant'), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Harvest plan'));
    expect(destination, 'harvest');
    await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));
    expect(destination, 'scan');
  });
}
