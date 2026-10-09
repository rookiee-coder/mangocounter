import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'features/history/data/history_database.dart';
import 'features/history/data/history_repository.dart';
import 'features/history/application/history_controller.dart';
import 'features/settings/application/settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final db = await HistoryDatabase.database;
  final historyRepo = HistoryRepository(db);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        historyRepositoryProvider.overrideWithValue(historyRepo),
      ],
      child: const MangoCountApp(),
    ),
  );
}
