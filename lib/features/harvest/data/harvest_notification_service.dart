import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/harvest_forecast.dart';
import '../domain/harvest_reminder.dart';

class HarvestNotificationService {
  HarvestNotificationService._();

  static final instance = HarvestNotificationService._();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    try {
      final zoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (_) {
      // The timezone package defaults to UTC if a device zone is unavailable.
    }
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_harvest'),
      ),
    );
    _initialized = true;
  }

  Future<bool> schedule(
    HarvestReminder reminder,
    HarvestForecast forecast,
  ) async {
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final permissionGranted = await android?.requestNotificationsPermission();
    if (permissionGranted == false) return false;

    final scheduled = tz.TZDateTime(
      tz.local,
      reminder.harvestDate.year,
      reminder.harvestDate.month,
      reminder.harvestDate.day,
      8,
    );
    final time = scheduled.isAfter(tz.TZDateTime.now(tz.local))
        ? scheduled
        : tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    await _notifications.zonedSchedule(
      reminder.notificationId,
      'Harvest reminder: ${forecast.treeLabel}',
      '${forecast.totalFruit} mangoes in the latest scan. ${forecast.summary}',
      time,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'harvest_reminders',
          'Harvest reminders',
          channelDescription: 'Planned mango harvest reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_harvest',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.treeId,
    );
    return true;
  }

  Future<void> cancel(HarvestReminder reminder) =>
      _notifications.cancel(reminder.notificationId);
}
