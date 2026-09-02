import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../school/models/school_rule.dart';
import '../models/daily_checkin.dart';

class CheckinSubmitResult {
  CheckinSubmitResult({required this.checkin, required this.isOverwrite});
  final DailyCheckin checkin;
  final bool isOverwrite;
}

class CheckinRepository {
  CheckinRepository();

  SupabaseClient get _c => SupabaseService.client;

  String _myUserId() {
    final u = _c.auth.currentUser;
    if (u == null) throw StateError('로그인 상태가 아닙니다.');
    return u.id;
  }

  Future<DailyCheckin?> fetchToday(String schoolId) async {
    final today = KstDate.formatYmd(KstDate.today());
    final row = await _c
        .from('daily_checkins')
        .select()
        .eq('user_id', _myUserId())
        .eq('checkin_date', today)
        .maybeSingle();
    return row == null ? null : DailyCheckin.fromMap(row);
  }

  Future<List<DailyCheckin>> fetchHistory({
    required int days,
  }) async {
    final since = KstDate.today().subtract(Duration(days: days - 1));
    final rows = await _c
        .from('daily_checkins')
        .select()
        .eq('user_id', _myUserId())
        .gte('checkin_date', KstDate.formatYmd(since))
        .order('checkin_date', ascending: false);
    return rows.map((m) => DailyCheckin.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<DailyCheckin>> fetchUserHistory({
    required String userId,
    required int days,
  }) async {
    final since = KstDate.today().subtract(Duration(days: days - 1));
    final rows = await _c
        .from('daily_checkins')
        .select()
        .eq('user_id', userId)
        .gte('checkin_date', KstDate.formatYmd(since))
        .order('checkin_date', ascending: false);
    return rows.map((m) => DailyCheckin.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<DailyCheckin>> fetchSchoolHistory({
    required String schoolId,
    required int days,
  }) async {
    final since = KstDate.today().subtract(Duration(days: days - 1));
    final rows = await _c
        .from('daily_checkins')
        .select()
        .eq('school_id', schoolId)
        .gte('checkin_date', KstDate.formatYmd(since))
        .order('checkin_date', ascending: false);
    return rows.map((m) => DailyCheckin.fromMap(m as Map<String, dynamic>)).toList();
  }

  /// 오늘 점검을 제출한다.
  ///
  /// 날짜·점수·포인트를 모두 서버가 정한다. 예전에는 앱이 기기 시간으로
  /// 날짜를 만들어 테이블에 직접 넣었는데, 기기 날짜를 바꾸면 임의의 날짜로
  /// 점검이 쌓여 포인트를 반복 취득할 수 있었다. 이제 앱은 답만 보낸다.
  Future<CheckinSubmitResult> submit({
    required String schoolId,
    required List<SchoolRule> rules,
    required Map<String, bool> answers,
    String? comment,
  }) async {
    // 우리 학교 규칙에 해당하는 답만 추린다 (나머지는 서버가 어차피 버린다)
    final ids = rules.map((r) => r.id).toSet();
    final payload = <String, bool>{
      for (final e in answers.entries)
        if (ids.contains(e.key)) e.key: e.value,
    };

    final res = await _c.rpc('submit_checkin',
        params: {'p_answers': payload, 'p_comment': comment});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '점검을 저장하지 못했어요');
    }

    final saved = await fetchToday(schoolId);
    if (saved == null) {
      throw StateError('저장은 됐지만 불러오지 못했어요. 새로고침해 주세요.');
    }
    return CheckinSubmitResult(
      checkin: saved,
      isOverwrite: (m['is_overwrite'] as bool?) ?? false,
    );
  }

  Future<int> totalCount() async {
    final rows = await _c
        .from('daily_checkins')
        .select('id')
        .eq('user_id', _myUserId());
    return rows.length;
  }
}
