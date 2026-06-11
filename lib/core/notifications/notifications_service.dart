import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for daily check-in reminders.
///
/// NOTE: For repeating daily scheduling pinned to a specific hour, add the
/// `timezone` package and switch to `zonedSchedule`. This service ships a
/// minimal init + an "immediate reminder" path so the app builds and runs out
/// of the box.
class NotificationsService {
  NotificationsService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'pbs_plus_reminder';

  static Future<void> initialize() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(initSettings);
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Show an immediate reminder. Wire this to a periodic background task
  /// or call from your homeroom-time trigger.
  static Future<void> showReminderNow() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        '자기점검 리마인더',
        channelDescription: '하루 한 번 자기점검을 잊지 않도록 알려드려요',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      1001,
      '오늘 자기점검 잊지 마세요! 🌱',
      '1분이면 충분해요. 지금 바로 시작해볼까요?',
      details,
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();
}
