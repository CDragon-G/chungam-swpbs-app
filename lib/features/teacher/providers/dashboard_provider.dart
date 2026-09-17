import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/providers/profile_provider.dart';

class SchoolOverview {
  SchoolOverview({
    required this.todayParticipationPct,
    required this.totalStudents,
    required this.todayParticipants,
    required this.weeklyAvg,
    required this.lastWeekAvg,
    required this.last14Days,
    required this.classParticipation,
    required this.categoryAverages,
  });

  final double todayParticipationPct;
  final int totalStudents;
  final int todayParticipants;
  final double weeklyAvg;
  final double lastWeekAvg;
  final List<({DateTime date, double avg, int participants})> last14Days;
  /// classKey "{grade}-{classNum}" -> participation pct today
  final Map<String, double> classParticipation;
  final Map<String, double> categoryAverages;

  double get weekDelta => weeklyAvg - lastWeekAvg;
}

/// 교사 홈 · 대시보드 요약 — 합계는 서버(RPC)에서 낸다.
/// 예전에는 전교 14일치 점검 원본(규칙별 O/X 포함)을 통째로 내려받아 앱에서
/// 계산했다. 1,500명 학교면 홈을 열 때마다 약 1만 건이라 서버 집계로 옮겼다.
final schoolOverviewProvider = FutureProvider<SchoolOverview>((ref) async {
  final profile = ref.watch(profileProvider).value;
  final empty = SchoolOverview(
    todayParticipationPct: 0,
    totalStudents: 0,
    todayParticipants: 0,
    weeklyAvg: 0,
    lastWeekAvg: 0,
    last14Days: const [],
    classParticipation: const {},
    categoryAverages: const {},
  );
  if (profile == null || profile.schoolId == null) return empty;

  final res = await SupabaseService.client.rpc('teacher_school_overview');
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) return empty;

  return SchoolOverview(
    todayParticipationPct: _d(m['today_pct']),
    totalStudents: _i(m['total_students']),
    todayParticipants: _i(m['today_participants']),
    weeklyAvg: _d(m['weekly_avg']),
    lastWeekAvg: _d(m['last_week_avg']),
    last14Days: [
      for (final r in (m['last14'] as List? ?? const []))
        (
          date: DateTime.parse((r as Map)['date'] as String),
          avg: _d(r['avg']),
          participants: _i(r['participants']),
        ),
    ],
    classParticipation: _doubleMap(m['class_participation']),
    categoryAverages: _doubleMap(m['category_averages']),
  );
});

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
Map<String, double> _doubleMap(Object? v) => {
      for (final e in (v as Map? ?? const {}).entries)
        e.key as String: _d(e.value),
    };

class ClassStats {
  ClassStats({
    required this.classKey,
    required this.studentCount,
    required this.participationByDay,
    required this.categoryAverages,
    required this.weakestRules,
    required this.nonParticipantsToday,
  });

  final String classKey;
  final int studentCount;
  final List<({DateTime date, int participants, int total})> participationByDay;
  final Map<String, double> categoryAverages;
  final List<({String ruleId, String text, double avgOk})> weakestRules;
  final List<({String nickname, int grade, int classNum, int studentNum})>
      nonParticipantsToday;
}

final selectedClassProvider = StateProvider<String?>((_) => null);

/// 반별 통계 — 이 반 학생 것만 서버에서 합쳐 온다.
/// 예전에는 반 하나를 열 때도 전교 14일치 원본을 다시 내려받았다.
final classStatsProvider =
    FutureProvider.family<ClassStats, String>((ref, classKey) async {
  final parts = classKey.split('-');
  final grade = int.tryParse(parts[0]);
  final classNum = parts.length > 1 ? int.tryParse(parts[1]) : null;
  final profile = ref.watch(profileProvider).value;
  final empty = ClassStats(
    classKey: classKey,
    studentCount: 0,
    participationByDay: const [],
    categoryAverages: const {},
    weakestRules: const [],
    nonParticipantsToday: const [],
  );
  if (profile?.schoolId == null || grade == null || classNum == null) {
    return empty;
  }

  final res = await SupabaseService.client.rpc(
    'teacher_class_stats',
    params: {'p_grade': grade, 'p_class': classNum},
  );
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) return empty;

  return ClassStats(
    classKey: classKey,
    studentCount: _i(m['student_count']),
    participationByDay: [
      for (final r in (m['by_day'] as List? ?? const []))
        (
          date: DateTime.parse((r as Map)['date'] as String),
          participants: _i(r['participants']),
          total: _i(r['total']),
        ),
    ],
    categoryAverages: _doubleMap(m['category_averages']),
    weakestRules: [
      for (final r in (m['weakest_rules'] as List? ?? const []))
        (
          ruleId: (r as Map)['rule_id'] as String,
          text: (r['text'] as String?) ?? '',
          avgOk: _d(r['avg_ok']),
        ),
    ],
    nonParticipantsToday: [
      for (final r in (m['non_participants_today'] as List? ?? const []))
        (
          nickname: ((r as Map)['nickname'] as String?) ?? '',
          grade: _i(r['grade']),
          classNum: _i(r['class_num']),
          studentNum: _i(r['student_num']),
        ),
    ],
  );
});

class StudentRow {
  StudentRow({
    required this.userId,
    required this.profileId,
    required this.nickname,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.streak,
    required this.lastCheckinDate,
    required this.avgScore,
    required this.badgeCount,
    required this.missedDays,
  });

  final String userId;
  final String profileId;
  final String nickname;
  final int grade;
  final int classNum;
  final int studentNum;
  final int streak;
  final DateTime? lastCheckinDate;
  final double avgScore;
  final int badgeCount;
  final int missedDays;
}

/// 학생 목록 — 집계를 서버(RPC)에서 처리한다.
/// 예전에는 전교 60일치 점검 기록을 전부 내려받아 앱에서 계산했는데,
/// 학생 수가 늘면 전송량과 연산량이 함께 폭증해 서버 집계로 옮겼다.
final studentRowsProvider = FutureProvider<List<StudentRow>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];

  final rows = await SupabaseService.client
      .rpc('student_rows', params: {'p_days': 60}) as List;

  return rows.map((r) {
    final m = Map<String, dynamic>.from(r as Map);
    final last = m['last_checkin_date'] as String?;
    return StudentRow(
      userId: m['user_id'] as String,
      profileId: m['profile_id'] as String,
      nickname: (m['nickname'] as String?) ?? '',
      grade: (m['grade'] as num?)?.toInt() ?? 0,
      classNum: (m['class_num'] as num?)?.toInt() ?? 0,
      studentNum: (m['student_num'] as num?)?.toInt() ?? 0,
      streak: (m['streak'] as num?)?.toInt() ?? 0,
      lastCheckinDate: last == null ? null : DateTime.parse(last),
      avgScore: (m['avg_score'] as num?)?.toDouble() ?? 0,
      badgeCount: (m['badge_count'] as num?)?.toInt() ?? 0,
      missedDays: (m['missed_days'] as num?)?.toInt() ?? 0,
    );
  }).toList();
});


