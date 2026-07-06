import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 로컬 알림: 학생 일일 자기점검 리마인더 (매일 지정 시각 반복).
///
/// 예약은 inexact 모드라 SCHEDULE_EXACT_ALARM 권한이 필요 없고, 몇 분 오차만 있어요.
/// 부팅 후 자동 복원은 AndroidManifest의 BootReceiver가 처리하고, 앱 실행 때마다도
/// ReminderPrefs.reschedule()로 한 번 더 보정해요.
class NotificationsService {
  NotificationsService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'pbs_plus_reminder';
  static const _reminderId = 1002;

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {/* 기본 로케이션 유지 */}

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(initSettings);
  }

  /// 알림 권한 요청 (Android 13+ / iOS). 허용되면 true.
  static Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '자기점검 리마인더',
      channelDescription: '하루 한 번 자기점검을 잊지 않도록 알려드려요',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// 매일 [hour]:[minute]에 반복되는 리마인더 예약.
  static Future<void> scheduleDailyReminder(int hour, int minute) async {
    await _plugin.cancel(_reminderId);
    await _plugin.zonedSchedule(
      _reminderId,
      '오늘 자기점검 잊지 마세요! 🌱',
      '1분이면 충분해요. 지금 바로 시작해볼까요?',
      _nextInstance(hour, minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // 매일 같은 시각 반복
    );
  }

  static Future<void> cancelReminder() => _plugin.cancel(_reminderId);

  static tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// 즉시 알림 (테스트/수동 트리거용).
  static Future<void> showReminderNow() async {
    await _plugin.show(
      1001,
      '오늘 자기점검 잊지 마세요! 🌱',
      '1분이면 충분해요. 지금 바로 시작해볼까요?',
      _details,
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();
}
