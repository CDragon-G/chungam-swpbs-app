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

  /// 기간별 현황 — 월별 · 이번 학년도 · 전체.
  ///
  /// 072 이전 서버에는 이 함수가 없다. 그때는 월별만 예전 함수로 보여준다.
  Future<KodrPeriodSummary> periodSubjects(KodrPeriod period) async {
    dynamic res;
    try {
      res = await _c.rpc('kodr_period_subjects', params: {
        'p_mode': period.mode.name,
        if (period.mode == KodrPeriodMode.month)
          'p_year_month': period.yearMonth,
      });
    } on PostgrestException catch (e) {
      final missing = e.code == 'PGRST202' || e.code == '42883';
      if (!missing || period.mode != KodrPeriodMode.month) rethrow;
      final items = await monthSubjects(yearMonth: period.yearMonth);
      return KodrPeriodSummary(
        items: items,
        months: const [],
        total: items.fold(0, (a, e) => a + e.recordCount),
      );
    }
    final m = _okOrThrow(res, '현황을 불러오지 못했어요');
    return KodrPeriodSummary(
      items: ((m['items'] as List?) ?? const [])
          .map((e) =>
              KodrSummaryEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      months: ((m['months'] as List?) ?? const [])
          .map((e) =>
              KodrMonthCount.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 한 학생의 누적 이력 — 달이 바뀌어도, 학년이 바뀌어도.
  Future<KodrHistory> subjectHistory(String subjectId) async {
    final m = _okOrThrow(
      await _c.rpc('kodr_subject_history', params: {'p_subject': subjectId}),
      '기록을 불러오지 못했어요',
    );
    return KodrHistory.fromMap(m);
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
