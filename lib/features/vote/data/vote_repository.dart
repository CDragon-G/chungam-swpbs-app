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
    final rows = await _c
        .from('vote_subjects')
        .select()
        .eq('school_id', schoolId)
        .order('order_index', ascending: true)
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
  }) async {
    await _c.from('vote_rounds').insert({
      'school_id': schoolId,
      'title': title.trim(),
      'votes_per_week': votesPerWeek,
    });
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
