import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../models/kodr.dart';

class KodrRepository {
  KodrRepository();
  SupabaseClient get _c => SupabaseService.client;

  String _myId() {
    final u = _c.auth.currentUser;
    if (u == null) throw StateError('로그인 상태가 아닙니다.');
    return u.id;
  }

  /// K-ODR 기록 작성 (교사).
  Future<void> create({
    required String schoolId,
    required String studentId,
    required DateTime occurredDate,
    required String behavior,
    String? place,
    String? situation,
    String? immediateResponse,
    String? secondaryResponse,
    String? studentReaction,
    String? authorRole,
    String? note,
  }) async {
    await _c.from('kodr_records').insert({
      'school_id': schoolId,
      'student_id': studentId,
      'teacher_id': _myId(),
      'occurred_date': KstDate.formatYmd(occurredDate),
      'behavior': behavior,
      if (place != null) 'place': place,
      if (situation != null) 'situation': situation,
      if (immediateResponse != null) 'immediate_response': immediateResponse,
      if (secondaryResponse != null) 'secondary_response': secondaryResponse,
      if (studentReaction != null) 'student_reaction': studentReaction,
      if (authorRole != null) 'author_role': authorRole,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  /// 월별 학생별 집계 (3건 이상 CICO 대상 식별).
  Future<List<KodrSummaryEntry>> monthlySummary(String schoolId,
      {String? yearMonth}) async {
    final rows = await _c.rpc('kodr_monthly_summary', params: {
      'p_school_id': schoolId,
      if (yearMonth != null) 'p_year_month': yearMonth,
    });
    return List<Map<String, dynamic>>.from(rows as List)
        .map(KodrSummaryEntry.fromMap)
        .toList();
  }

  /// 특정 학생의 K-ODR 기록 목록.
  Future<List<KodrRecord>> studentRecords(String studentId,
      {int limit = 50}) async {
    final rows = await _c
        .from('kodr_records')
        .select()
        .eq('student_id', studentId)
        .order('occurred_date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows)
        .map(KodrRecord.fromMap)
        .toList();
  }
}
