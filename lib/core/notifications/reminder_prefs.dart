import 'package:shared_preferences/shared_preferences.dart';

import '../supabase/supabase_client.dart';
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
      await _scheduleSchoolDaysOnly(hour, minute);
    } else {
      await NotificationsService.cancelReminder();
    }
  }

  /// 앱 시작 시 재예약 보정 (켜져 있으면 다시 예약).
  static Future<void> reschedule() async {
    final s = await load();
    if (s.enabled) {
      await _scheduleSchoolDaysOnly(s.hour, s.minute);
    }
  }

  /// 주말·공휴일·방학·재량휴업일을 뺀 '수업일'에만 알림을 예약한다.
  /// 서버에서 앞으로 3주치 수업일을 받아 하루씩 개별 예약하는 방식.
  /// 서버 조회에 실패하면 평일(월~금) 기준으로 대신 예약한다.
  static Future<void> _scheduleSchoolDaysOnly(int hour, int minute) async {
    try {
      final rows = await SupabaseService.client
          .rpc('upcoming_school_days', params: {'p_days': 21});
      final days =
          (rows as List).map((d) => DateTime.parse(d as String)).toList();
      if (days.isNotEmpty) {
        await NotificationsService.scheduleSchoolDayReminders(days, hour, minute);
        return;
      }
    } catch (_) {
      // 로그인 전이거나 오프라인 — 아래 평일 기준으로 대체
    }
    await NotificationsService.scheduleSchoolDayReminders(
      _weekdaysAhead(21),
      hour,
      minute,
    );
  }

  /// 서버를 못 읽을 때 쓰는 대체안 — 앞으로 n일 중 평일만.
  static List<DateTime> _weekdaysAhead(int n) {
    final today = DateTime.now();
    return [
      for (var i = 0; i < n; i++)
        if (today.add(Duration(days: i)).weekday <= DateTime.friday)
          today.add(Duration(days: i)),
    ];
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
