import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

/// 우리 학교에 있는 학급 목록 (담임 학급을 고를 때 사용).
final schoolClassListProvider =
    FutureProvider<List<ClassOption>>((ref) async {
  final rows = await SupabaseService.client.rpc('school_class_list') as List;
  return rows
      .map((r) => ClassOption.fromMap(Map<String, dynamic>.from(r as Map)))
      .toList();
});

/// 우리 반 현황 — 요약과 학생 목록을 한 번에 받는다.
final homeroomOverviewProvider =
    FutureProvider<HomeroomOverview>((ref) async {
  final res = await SupabaseService.client
      .rpc('homeroom_overview', params: {'p_days': 30});
  return HomeroomOverview.fromMap(Map<String, dynamic>.from(res as Map));
});

class HomeroomRepository {
  final _c = SupabaseService.client;

  /// 내 담임 학급을 지정한다. null 을 넣으면 해제.
  Future<void> setHomeroom({int? grade, int? classNum}) async {
    final res = await _c.rpc('set_my_homeroom',
        params: {'p_grade': grade, 'p_class': classNum});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '설정하지 못했어요');
    }
  }
}

final homeroomRepositoryProvider = Provider((ref) => HomeroomRepository());

// ── 모델 ──────────────────────────────────────────────────

class ClassOption {
  const ClassOption({
    required this.grade,
    required this.classNum,
    required this.studentCount,
  });

  final int grade;
  final int classNum;
  final int studentCount;

  String get label => '$grade학년 $classNum반';

  factory ClassOption.fromMap(Map<String, dynamic> m) => ClassOption(
        grade: (m['grade'] as num).toInt(),
        classNum: (m['class_num'] as num).toInt(),
        studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
      );
}

class HomeroomOverview {
  const HomeroomOverview({
    required this.ok,
    this.reason,
    this.grade,
    this.classNum,
    this.days = 30,
    this.schoolDays = 0,
    this.total = 0,
    this.todayDone = 0,
    this.todayPct = 0,
    this.avgParticipation = 0,
    this.avgScore = 0,
    this.totalPoints = 0,
    this.students = const [],
  });

  final bool ok;
  final String? reason; // not_teacher | no_homeroom
  final int? grade;
  final int? classNum;
  final int days;        // 조회 기간
  final int schoolDays;  // 그중 수업일 수 (참여율 분모)
  final int total;
  final int todayDone;
  final int todayPct;
  final int avgParticipation;
  final int avgScore;
  final int totalPoints;
  final List<HomeroomStudent> students;

  /// 담임 학급을 아직 정하지 않은 상태인가.
  bool get needsSetup => !ok && reason == 'no_homeroom';

  String get classLabel =>
      (grade == null || classNum == null) ? '' : '$grade학년 $classNum반';

  factory HomeroomOverview.fromMap(Map<String, dynamic> m) => HomeroomOverview(
        ok: (m['ok'] as bool?) ?? false,
        reason: m['reason'] as String?,
        grade: (m['grade'] as num?)?.toInt(),
        classNum: (m['class_num'] as num?)?.toInt(),
        days: (m['days'] as num?)?.toInt() ?? 30,
        schoolDays: (m['school_days'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        todayDone: (m['today_done'] as num?)?.toInt() ?? 0,
        todayPct: (m['today_pct'] as num?)?.toInt() ?? 0,
        avgParticipation: (m['avg_participation'] as num?)?.toInt() ?? 0,
        avgScore: (m['avg_score'] as num?)?.toInt() ?? 0,
        totalPoints: (m['total_points'] as num?)?.toInt() ?? 0,
        students: ((m['students'] as List?) ?? const [])
            .map((e) =>
                HomeroomStudent.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class HomeroomStudent {
  const HomeroomStudent({
    required this.userId,
    required this.profileId,
    required this.nickname,
    required this.studentNum,
    required this.days,
    required this.partPct,
    required this.avgScore,
    required this.todayDone,
    required this.streak,
    required this.points,
    required this.badges,
    required this.missed,
    this.lastDate,
  });

  final String userId;
  final String profileId;
  final String nickname;
  final int studentNum;
  final int days;      // 기간 내 참여 일수
  final int partPct;   // 참여율 %
  final int avgScore;  // 평균 점수 %
  final bool todayDone;
  final int streak;
  final int points;
  final int badges;
  final int missed;    // 마지막 점검 이후 지난 날
  final DateTime? lastDate;

  /// 한 번도 점검하지 않았는가.
  bool get neverChecked => days == 0;

  /// 관심이 필요한 학생 (3일 이상 미점검 또는 참여율 50% 미만).
  bool get needsAttention => neverChecked || missed >= 3 || partPct < 50;

  factory HomeroomStudent.fromMap(Map<String, dynamic> m) {
    final last = m['last_date'] as String?;
    return HomeroomStudent(
      userId: m['user_id'] as String,
      profileId: m['profile_id'] as String,
      nickname: (m['nickname'] as String?) ?? '',
      studentNum: (m['student_num'] as num?)?.toInt() ?? 0,
      days: (m['days'] as num?)?.toInt() ?? 0,
      partPct: (m['part_pct'] as num?)?.toInt() ?? 0,
      avgScore: (m['avg_score'] as num?)?.toInt() ?? 0,
      todayDone: (m['today_done'] as bool?) ?? false,
      streak: (m['streak'] as num?)?.toInt() ?? 0,
      points: (m['points'] as num?)?.toInt() ?? 0,
      badges: (m['badges'] as num?)?.toInt() ?? 0,
      missed: (m['missed'] as num?)?.toInt() ?? 999,
      lastDate: last == null ? null : DateTime.parse(last),
    );
  }
}
