import 'package:shared_preferences/shared_preferences.dart';

import 'notifications_service.dart';

/// 학생 일일 리마인더 설정 (기기 로컬 저장 + 예약 반영).
class ReminderPrefs {
  ReminderPrefs._();

  static const _kEnabled = 'reminder_enabled';
  static const _kHour = 'reminder_hour';
  static const _kMinute = 'reminder_minute';

  static Future<({bool enabled, int hour, int minute})> load() async {
    final p = await SharedPreferences.getInstance();
    return (
      enabled: p.getBool(_kEnabled) ?? false,
      hour: p.getInt(_kHour) ?? 17,
      minute: p.getInt(_kMinute) ?? 0,
    );
  }

  /// 설정 저장 + 즉시 반영(예약/취소).
  static Future<void> save({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setInt(_kHour, hour);
    await p.setInt(_kMinute, minute);
    if (enabled) {
      await NotificationsService.scheduleDailyReminder(hour, minute);
    } else {
      await NotificationsService.cancelReminder();
    }
  }

  /// 앱 시작 시 재예약 보정 (켜져 있으면 다시 예약).
  static Future<void> reschedule() async {
    final s = await load();
    if (s.enabled) {
      await NotificationsService.scheduleDailyReminder(s.hour, s.minute);
    }
  }

  /// 학생 첫 로그인 시 기본 ON (opt-out).
  /// 아직 한 번도 설정한 적 없을 때만 켠다 — 학생이 껐다면 존중.
  /// 교사에게는 점검 알림이 가면 안 되므로 학생 화면에서만 호출할 것.
  static Future<void> ensureDefaultOnForStudent() async {
    final p = await SharedPreferences.getInstance();
    if (p.containsKey(_kEnabled)) return; // 이미 사용자가 선택함
    final granted = await NotificationsService.requestPermission();
    await save(enabled: granted, hour: 17, minute: 0);
  }
}
