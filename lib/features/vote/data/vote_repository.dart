import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/vote_models.dart';

class VoteRepository {
  VoteRepository();

  SupabaseClient get _c => SupabaseService.client;

  /// KST 기준 ISO 주차 키 ('IYYY-IW') — 서버 kst_week_key()와 동일 규칙.
  static String currentWeekKey() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    // ISO 8601: 그 주의 목요일이 속한 연도가 ISO 연도
    final thursday = kst.add(Duration(days: 4 - (kst.weekday == 7 ? 7 : kst.weekday)));
    final firstDay = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
    return '${thursday.year}-${week.toString().padLeft(2, '0')}';
  }

  // ── 과목 ─────────────────────────────────────────────────
  Future<List<VoteSubject>> fetchSubjects(String schoolId) async {
    // 추가 순서와 무관하게 항상 ㄱㄴㄷ순 정렬
    final rows = await _c
        .from('vote_subjects')
        .select()
        .eq('school_id', schoolId)
        .order('name', ascending: true);
    return rows.map((m) => VoteSubject.fromMap(m)).toList();
  }

  Future<void> addSubject(String schoolId, String name, int orderIndex) async {
    await _c.from('vote_subjects').insert({
      'school_id': schoolId,
      'name': name.trim(),
      'order_index': orderIndex,
    });
  }

  Future<void> deleteSubject(String id) async {
    await _c.from('vote_subjects').delete().eq('id', id);
  }

  // ── 라운드 ───────────────────────────────────────────────
  Future<List<VoteRound>> fetchRounds(String schoolId) async {
    final rows = await _c
        .from('vote_rounds')
        .select()
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .limit(10);
    return rows.map((m) => VoteRound.fromMap(m)).toList();
  }

  Future<void> createRound({
    required String schoolId,
    required String title,
    required int votesPerWeek,
    required int totalWeeks,
  }) async {
    await _c.from('vote_rounds').insert({
      'school_id': schoolId,
      'title': title.trim(),
      'votes_per_week': votesPerWeek,
      'total_weeks': totalWeeks,
    });
  }

  /// 진행 중 라운드 재미 힌트 (교사·학생 공용).
  Future<VoteHint> fetchHint() async {
    final res = await _c.rpc('vote_hint');
    return VoteHint.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// 우리 학교에 실제로 있는 학년 (학생 프로필 기준).
  Future<List<int>> fetchGrades(String schoolId) async {
    final res = await _c.rpc('school_grades', params: {'p_school': schoolId});
    return ((res as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
  }

  /// 라운드 진행 현황 — 오늘 투표 가능 여부 + 학년별 주차·쉬는 기간·마감.
  Future<VoteProgress> roundProgress(String roundId) async {
    final res = await _c
        .rpc('vote_round_progress', params: {'p_round_id': roundId});
    return VoteProgress.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// 진행 중인 투표를 수정한다 (이름·투표권·주차·투표 가능한 날).
  Future<void> updateRound({
    required String roundId,
    required String title,
    required int votesPerWeek,
    required int totalWeeks,
    DateTime? startDate,
    DateTime? endDate,
    List<int>? weekdays,
  }) async {
    final res = await _c.rpc('update_vote_round', params: {
      'p_round_id': roundId,
      'p_title': title,
      'p_votes_per_week': votesPerWeek,
      'p_total_weeks': totalWeeks,
      'p_start_date': _ymd(startDate),
      'p_end_date': _ymd(endDate),
      'p_weekdays': (weekdays == null || weekdays.isEmpty) ? null : weekdays,
    });
    _throwIfFailed(res);
  }

  /// 라운드를 지운다. 그 라운드의 투표 기록도 함께 사라진다.
  Future<int> deleteRound(String roundId) async {
    final res =
        await _c.rpc('delete_vote_round', params: {'p_round_id': roundId});
    _throwIfFailed(res);
    final m = Map<String, dynamic>.from(res as Map);
    return (m['deleted_votes'] as num?)?.toInt() ?? 0;
  }

  /// 우리 학교 교사들에게 투표 안내 알림을 보낸다.
  /// 알림 센터에 기록한 뒤, 푸시는 Edge Function 이 맡는다.
  Future<String> sendNotice({required String roundId, String? body}) async {
    final res = await _c.rpc('send_vote_notice', params: {
      'p_round_id': roundId,
      'p_body': body,
    });
    _throwIfFailed(res);
    final m = Map<String, dynamic>.from(res as Map);
    final sentBody = (m['body'] as String?) ?? '';
    // 푸시 실패가 안내 기록까지 되돌리지는 않게 결과를 기다리지 않는다.
    unawaited(
      _c.functions.invoke('send-vote-notice', body: {
        'title': '🍽️ 수업맛집 투표 안내',
        'body': sentBody,
      }).then((_) {}).catchError((_) {}),
    );
    return sentBody;
  }

  static String? _ymd(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  /// 이 학년만 먼저 마감(또는 마감 취소).
  Future<void> setGradeClosed({
    required String roundId,
    required int grade,
    required bool closed,
  }) async {
    final res = await _c.rpc('set_vote_grade_close', params: {
      'p_round_id': roundId,
      'p_grade': grade,
      'p_closed': closed,
    });
    _throwIfFailed(res);
  }

  /// 이 학년만 총 주차를 따로 정한다. null 이면 라운드 기본값으로 되돌린다.
  Future<void> setGradeWeeks({
    required String roundId,
    required int grade,
    int? weeks,
  }) async {
    final res = await _c.rpc('set_vote_grade_weeks', params: {
      'p_round_id': roundId,
      'p_grade': grade,
      'p_weeks': weeks,
    });
    _throwIfFailed(res);
  }

  void _throwIfFailed(dynamic res) {
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '처리하지 못했어요');
    }
  }

  // ── 투표 쉬는 기간 (시험 기간 등) ─────────────────────────
  Future<List<VoteBlackout>> fetchBlackouts(String schoolId) async {
    final rows = await _c
        .from('vote_blackouts')
        .select()
        .eq('school_id', schoolId)
        .order('start_date', ascending: true);
    return rows.map((m) => VoteBlackout.fromMap(m)).toList();
  }

  Future<void> addBlackout({
    required String schoolId,
    required int? grade,
    required DateTime startDate,
    required DateTime endDate,
    required String label,
  }) async {
    await _c.from('vote_blackouts').insert({
      'school_id': schoolId,
      'grade': grade,
      'start_date': _ymd(startDate),
      'end_date': _ymd(endDate),
      'label': label.trim().isEmpty ? '시험 기간' : label.trim(),
      'created_by': _c.auth.currentUser?.id,
    });
  }

  Future<void> deleteBlackout(String id) async {
    await _c.from('vote_blackouts').delete().eq('id', id);
  }

  Future<void> closeRound(String id) async {
    await _c.from('vote_rounds').update({
      'status': 'closed',
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // ── 투표 ─────────────────────────────────────────────────
  Future<void> castVote({
    required String roundId,
    required String subject,
    required int grade,
    required int classNum,
  }) async {
    await _c.rpc('cast_class_vote', params: {
      'p_round_id': roundId,
      'p_subject': subject,
      'p_grade': grade,
      'p_class_num': classNum,
    });
  }

  Future<void> deleteVote(String id) async {
    await _c.from('class_votes').delete().eq('id', id);
  }

  /// 내 투표 (라운드 전체, 최신순).
  Future<List<ClassVote>> myVotes(String roundId) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('class_votes')
        .select()
        .eq('round_id', roundId)
        .eq('teacher_id', uid)
        .order('created_at', ascending: false);
    return rows.map((m) => ClassVote.fromMap(m)).toList();
  }

  /// 집계 (열림: 관리자만 / 마감: 전체 교사) — 서버 검증.
  Future<List<VoteTallyRow>> tally(String roundId) async {
    final rows =
        await _c.rpc('vote_tally', params: {'p_round_id': roundId}) as List;
    return rows
        .map((m) => VoteTallyRow.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }
}
