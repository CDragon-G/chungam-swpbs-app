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

  /// UPSERT today's check-in (overwrite same-day).
  Future<CheckinSubmitResult> submit({
    required String schoolId,
    required List<SchoolRule> rules,
    required Map<String, bool> answers,
    String? comment,
  }) async {
    final today = KstDate.formatYmd(KstDate.today());

    int totalPossible = 0;
    int totalScore = 0;
    final perCategory = <String, List<int>>{};
    for (final r in rules) {
      final ans = answers[r.id];
      if (ans == null) continue;
      totalPossible++;
      final val = ans ? 1 : 0;
      totalScore += val;
      perCategory.putIfAbsent(r.category, () => []).add(val);
    }
    final scorePct =
        totalPossible == 0 ? 0.0 : (totalScore / totalPossible) * 100.0;
    final categoryScores = <String, double>{
      for (final e in perCategory.entries)
        e.key: e.value.isEmpty
            ? 0.0
            : (e.value.reduce((a, b) => a + b) / e.value.length) * 100.0,
    };

    final payload = {
      'user_id': _myUserId(),
      'school_id': schoolId,
      'checkin_date': today,
      'answers': answers,
      'total_score': totalScore,
      'total_possible': totalPossible,
      'score_pct': scorePct,
      'category_scores': categoryScores,
      'comment': comment,
    };

    final existing = await fetchToday(schoolId);
    final row = await _c
        .from('daily_checkins')
        .upsert(payload, onConflict: 'user_id,checkin_date')
        .select()
        .single();
    return CheckinSubmitResult(
      checkin: DailyCheckin.fromMap(row),
      isOverwrite: existing != null,
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
