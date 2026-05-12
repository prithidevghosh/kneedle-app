import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notification scheduler. Invoked by Gemma function calls
/// (`schedule_reminder`, `add_medication`, `add_appointment`) and by the
/// exercise screen's "remind me tomorrow" affordance.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  // Android Notification flag constants. FLAG_INSISTENT (4) keeps the
  // notification sound looping until the user dismisses it — turns a passive
  // notification into something that behaves like a real alarm clock.
  static final Int32List _insistentFlags = Int32List.fromList([4]);

  // 10-minute auto-dismiss so an unattended alarm doesn't ring forever.
  static const int _alarmTimeoutMs = 10 * 60 * 1000;

  static Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // Fallback to UTC — schedules will still fire at the right absolute time.
    }

    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(init);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _initialised = true;
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await init();
    final scheduled = tz.TZDateTime.from(when, tz.local);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'kneedle_reminders',
        'Kneedle reminders',
        channelDescription: 'Exercise & medication reminders from Kneedle.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule an *alarm-style* daily notification: full-screen intent, looping
  /// alarm-channel sound (FLAG_INSISTENT), vibration, and a 10-minute timeout
  /// so the patient is hard to miss but the device isn't woken indefinitely.
  /// Used for medication reminders where a silent banner isn't enough.
  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour,
        minute);
    if (!first.isAfter(now)) {
      first = first.add(const Duration(days: 1));
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'kneedle_medication_alarm',
        'Medication alarms',
        channelDescription:
            'Loud, alarm-style daily medication reminders. Rings until you '
            'tap or for up to 10 minutes.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        // FLAG_INSISTENT — loops the sound until the user dismisses.
        additionalFlags: _insistentFlags,
        timeoutAfter: _alarmTimeoutMs,
        ongoing: false,
        autoCancel: true,
        visibility: NotificationVisibility.public,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      first,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
  static Future<void> cancelAll() => _plugin.cancelAll();
}
