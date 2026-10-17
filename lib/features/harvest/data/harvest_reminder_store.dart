import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/harvest_reminder.dart';

class HarvestReminderStore {
  static const _storageKey = 'harvest_reminders_v1';
  final SharedPreferences _preferences;

  HarvestReminderStore(this._preferences);

  Map<String, HarvestReminder> load() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) return {};
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      final reminders = <String, HarvestReminder>{};
      for (final value in values.whereType<Map<String, dynamic>>()) {
        final reminder = HarvestReminder.fromJson(value);
        reminders[reminder.treeId] = reminder;
      }
      return reminders;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, HarvestReminder> reminders) {
    return _preferences.setString(
      _storageKey,
      jsonEncode(reminders.values.map((reminder) => reminder.toJson()).toList()),
    );
  }
}
