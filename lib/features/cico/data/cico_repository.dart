import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../models/cico.dart';

class CicoRepository {
  CicoRepository();
  SupabaseClient get _c => SupabaseService.client;

  // ── 등록 관리 ─────────────────────────────────────────────

  /// CICO 시작 (교사). enrollment id 반환.
  Future<String> start({
    required String studentUserId,
    String? mentorId,
    int goalPct = 80,
    String? reason,
  }) async {
    final res = await _c.rpc('cico_start', params: {
      'p_student_user_id': studentUserId,
      'p_mentor_id': mentorId,
      'p_goal_pct': goalPct,
      'p_reason': reason,
    });
    return res as String;
  }

  /// 학교의 CICO 등록 목록 (교사). 이름은 profiles에서 별도 조회해 채움.
  Future<List<CicoEnrollment>> listForSchool(String schoolId,
      {bool activeOnly = true}) async {
    var query =
        _c.from('cico_enrollments').select().eq('school_id', schoolId);
    if (activeOnly) query = query.eq('status', 'active');
    final rows = await query.order('created_at', ascending: false);
    final enrollments = List<Map<String, dynamic>>.from(rows)
        .map(CicoEnrollment.fromMap)
        .toList();
    if (enrollments.isEmpty) return enrollments;

    // 학생·멘토 이름 조회 (실패해도 목록 자체는 반환)
    try {
      final ids = <String>{
        for (final e in enrollments) e.studentId,
        for (final e in enrollments)
          if (e.mentorId != null) e.mentorId!,
      }.toList();
      final profs = await _c
          .from('profiles')
          .select('user_id, nickname, grade, class_num, student_num, role')
          .inFilter('user_id', ids);
      final byId = {
        for (final p in List<Map<String, dynamic>>.from(profs))
          p['user_id'] as String: p,
      };
      return enrollments.map((e) {
        final sp = byId[e.studentId];
        final mp = e.mentorId == null ? null : byId[e.mentorId];
        return e.withNames(
          studentName: sp?['nickname'] as String?,
          studentLabel: sp == null
              ? null
              : '${sp['grade']}-${sp['class_num']}-${sp['student_num']}',
          mentorName: mp?['nickname'] as String?,
        );
      }).toList();
    } catch (_) {
      return enrollments;
    }
  }

  /// 학생 본인의 진행 중 CICO (없으면 null).
  Future<CicoEnrollment?> myActiveEnrollment() async {
    final u = _c.auth.currentUser;
    if (u == null) return null;
    final rows = await _c
        .from('cico_enrollments')
        .select()
        .eq('student_id', u.id)
        .eq('status', 'active')
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;
    return CicoEnrollment.fromMap(list.first);
  }

  /// 졸업/중단 처리 (교사).
  Future<void> setStatus(String enrollmentId, String status) async {
    await _c.rpc('cico_set_status', params: {
      'p_enrollment_id': enrollmentId,
      'p_status': status,
    });
  }

  // ── 일일 카드 ─────────────────────────────────────────────

  /// 특정 날짜의 카드 조회 (없으면 null).
  Future<CicoDaily?> fetchDaily(String enrollmentId, DateTime date) async {
    final rows = await _c
        .from('cico_daily')
        .select()
        .eq('enrollment_id', enrollmentId)
        .eq('entry_date', KstDate.formatYmd(date))
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;
    return CicoDaily.fromMap(list.first);
  }

  /// 카드의 항목별 점수 조회.
  Future<List<CicoScore>> fetchScores(String dailyId) async {
    final rows = await _c
        .from('cico_scores')
        .select()
        .eq('daily_id', dailyId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows)
        .map(CicoScore.fromMap)
        .toList();
  }

  /// 하루 기록 저장 (교사): 체크인/체크아웃 + 점수. 달성률 반환.
  Future<double> saveDay({
    required String enrollmentId,
    required DateTime date,
    String? checkin,
    String? checkout,
    required List<CicoScoreInput> scores,
  }) async {
    final res = await _c.rpc('cico_save_day', params: {
      'p_enrollment_id': enrollmentId,
      'p_entry_date': KstDate.formatYmd(date),
      'p_checkin': checkin,
      'p_checkout': checkout,
      'p_scores': scores.map((s) => s.toJson()).toList(),
    });
    if (res is Map && res['pct'] != null) {
      final v = res['pct'];
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }
    return 0;
  }

  /// 학생 소감 + 보호자 서명 저장 (학생 본인).
  Future<void> studentNote({
    required String dailyId,
    String? reflection,
    String? signatureBase64,
  }) async {
    await _c.rpc('cico_student_note', params: {
      'p_daily_id': dailyId,
      'p_reflection': reflection,
      'p_signature': signatureBase64,
    });
  }

  /// 진전도 이력 (그래프용, 최근 n일).
  Future<List<CicoDaily>> history(String enrollmentId, {int limit = 30}) async {
    final rows = await _c
        .from('cico_daily')
        .select()
        .eq('enrollment_id', enrollmentId)
        .order('entry_date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows)
        .map(CicoDaily.fromMap)
        .toList()
        .reversed
        .toList();
  }
}
