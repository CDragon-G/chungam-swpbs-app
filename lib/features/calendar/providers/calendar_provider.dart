import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_prefs.dart';
import '../../../core/supabase/supabase_client.dart';

/// 오늘이 수업일인지 (주말·공휴일·방학·재량휴업일 판정 결과).
class SchoolDayStatus {
  const SchoolDayStatus({
    required this.isSchoolDay,
    this.reason,
    this.label,
  });

  final bool isSchoolDay;
  final String? reason; // weekend | holiday | closure
  final String? label; // '토요일' · '추석' · '여름방학'

  /// 학생에게 보여줄 한 줄 안내.
  String get message => switch (reason) {
        'weekend' => '오늘은 $label이에요. 푹 쉬어요! 🌿',
        'holiday' => '오늘은 $label이라 쉬는 날이에요 🌿',
        'closure' => '오늘은 $label 기간이에요. 푹 쉬어요! 🌿',
        _ => '오늘은 쉬는 날이에요 🌿',
      };

  /// 교사에게 보여줄 한 줄 안내.
  String get teacherMessage => switch (reason) {
        'weekend' => '오늘은 $label — 자기점검이 열리지 않아요',
        'holiday' => '오늘은 $label — 자기점검이 열리지 않아요',
        'closure' => '$label 기간 — 자기점검이 열리지 않아요',
        _ => '오늘은 수업일이 아니에요',
      };

  factory SchoolDayStatus.fromMap(Map<String, dynamic> m) => SchoolDayStatus(
        isSchoolDay: m['is_school_day'] as bool? ?? true,
        reason: m['reason'] as String?,
        label: m['label'] as String?,
      );
}

/// 오늘 수업일 여부 — 홈·점검 화면에서 사용.
final todaySchoolStatusProvider =
    FutureProvider<SchoolDayStatus>((ref) async {
  try {
    final res = await SupabaseService.client.rpc('today_school_status');
    return SchoolDayStatus.fromMap(Map<String, dynamic>.from(res as Map));
  } catch (_) {
    // 서버 확인 실패 시에는 평소처럼 동작 (점검을 막지 않는다)
    return const SchoolDayStatus(isSchoolDay: true);
  }
});

/// 우리 학교 휴업일 목록 (관리자 화면).
final schoolClosuresProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await SupabaseService.client
      .from('school_closures')
      .select()
      .order('start_date');
  return List<Map<String, dynamic>>.from(rows);
});

/// 공휴일 목록 (올해 이후만, 관리자 화면에서 참고용).
final publicHolidaysProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final from = DateTime.now().subtract(const Duration(days: 30));
  final rows = await SupabaseService.client
      .from('public_holidays')
      .select()
      .gte('holiday_date', from.toIso8601String().substring(0, 10))
      .order('holiday_date')
      .limit(40);
  return List<Map<String, dynamic>>.from(rows);
});

/// 📅 학생 일일 리마인더를 '수업일에만' 다시 예약한다.
/// 매일 반복 알림 대신 앞으로 3주치를 하루씩 개별 예약해서
/// 주말·공휴일·방학에는 알림이 가지 않게 한다.
/// 앱을 열 때마다 호출하면 항상 3주치가 유지된다.
Future<void> syncStudentReminders() async {
  try {
    await ReminderPrefs.reschedule();
  } catch (_) {
    // 알림은 부가 기능 — 실패해도 앱 사용에 지장 없음
  }
}

/// 휴업일 등록·삭제 (관리자).
class CalendarRepository {
  final _c = SupabaseService.client;

  Future<void> addClosure({
    required String schoolId,
    required DateTime start,
    required DateTime end,
    required String label,
  }) =>
      _c.from('school_closures').insert({
        'school_id': schoolId,
        'start_date': start.toIso8601String().substring(0, 10),
        'end_date': end.toIso8601String().substring(0, 10),
        'label': label,
        'created_by': _c.auth.currentUser!.id,
      });

  Future<void> deleteClosure(String id) =>
      _c.from('school_closures').delete().eq('id', id);
}

final calendarRepositoryProvider = Provider((ref) => CalendarRepository());
