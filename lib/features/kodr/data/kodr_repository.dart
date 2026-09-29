import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../models/kodr.dart';

class KodrRepository {
  KodrRepository();
  SupabaseClient get _c => SupabaseService.client;

  Map<String, dynamic> _okOrThrow(dynamic res, String fallback) {
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? fallback);
    }
    return m;
  }

  /// K-ODR 을 고를 수 있는 학생 — 명렬표 전체 (가입하지 않은 학생 포함).
  Future<List<KodrStudentOption>> studentOptions() async {
    final m =
        _okOrThrow(await _c.rpc('kodr_student_options'), '학생 명단을 불러오지 못했어요');
    return ((m['items'] as List?) ?? const [])
        .map((e) =>
            KodrStudentOption.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// K-ODR 기록 작성 (교사). 여러 학생을 골랐으면 학생마다 한 건씩 같은 내용으로.
  /// 하나라도 문제가 있으면 서버가 아무것도 저장하지 않는다.
  Future<int> createMany({
    required List<String> rosterIds,
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
    final m = _okOrThrow(
      await _c.rpc('create_kodr_records', params: {
        'p_roster_ids': rosterIds,
        'p_occurred_date': KstDate.formatYmd(occurredDate),
        'p_behavior': behavior,
        'p_place': place,
        'p_situation': situation,
        'p_immediate': immediateResponse,
        'p_secondary': secondaryResponse,
        'p_reaction': studentReaction,
        'p_author_role': authorRole,
        'p_note': (note == null || note.isEmpty) ? null : note,
      }),
      '기록하지 못했어요',
    );
    return (m['count'] as num?)?.toInt() ?? rosterIds.length;
  }

  /// 월별 학생별 집계 (가입하지 않은 학생 포함).
  Future<List<KodrSummaryEntry>> monthSubjects({String? yearMonth}) async {
    final m = _okOrThrow(
      await _c.rpc('kodr_month_subjects', params: {
        if (yearMonth != null) 'p_year_month': yearMonth,
      }),
      '이달 현황을 불러오지 못했어요',
    );
    return ((m['items'] as List?) ?? const [])
        .map((e) =>
            KodrSummaryEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 한 학생의 K-ODR 기록 목록 (가입 여부와 상관없이).
  Future<List<KodrRecord>> subjectRecords(String subjectId,
      {int limit = 50}) async {
    final m = _okOrThrow(
      await _c.rpc('kodr_subject_records',
          params: {'p_subject': subjectId, 'p_limit': limit}),
      '기록을 불러오지 못했어요',
    );
    return ((m['items'] as List?) ?? const [])
        .map((e) => KodrRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
