import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../checkin/models/daily_checkin.dart';
import '../../checkin/providers/checkin_provider.dart';
import '../../school/providers/school_provider.dart';

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

final schoolOverviewProvider = FutureProvider<SchoolOverview>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile.schoolId == null) {
    return SchoolOverview(
      todayParticipationPct: 0,
      totalStudents: 0,
      todayParticipants: 0,
      weeklyAvg: 0,
      lastWeekAvg: 0,
      last14Days: const [],
      classParticipation: const {},
      categoryAverages: const {},
    );
  }
  final schoolId = profile.schoolId!;
  final students = await ref.read(schoolStudentsProvider.future);
  final repo = ref.read(checkinRepositoryProvider);
  final history = await repo.fetchSchoolHistory(schoolId: schoolId, days: 14);

  final today = KstDate.today();
  bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Today
  final todayCheckins =
      history.where((c) => isSameDate(c.checkinDate, today)).toList();
  final todayParticipants = todayCheckins.map((c) => c.userId).toSet().length;
  final totalStudents = students.length;
  final todayPct =
      totalStudents == 0 ? 0.0 : (todayParticipants / totalStudents) * 100;

  // 14-day trend
  final last14 = <({DateTime date, double avg, int participants})>[];
  for (var i = 13; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final dayCh = history.where((c) => isSameDate(c.checkinDate, d)).toList();
    final avg = dayCh.isEmpty
        ? 0.0
        : dayCh.map((c) => c.scorePct).reduce((a, b) => a + b) / dayCh.length;
    last14.add((date: d, avg: avg, participants: dayCh.length));
  }

  // Class participation (today)
  final classMap = <String, ({int students, Set<String> participants})>{};
  for (final s in students) {
    final key = '${s['grade']}-${s['class_num']}';
    classMap.putIfAbsent(
      key,
      () => (students: 0, participants: <String>{}),
    );
    final cur = classMap[key]!;
    classMap[key] = (
      students: cur.students + 1,
      participants: cur.participants,
    );
  }
  for (final c in todayCheckins) {
    final s = students.firstWhere(
      (st) => st['user_id'] == c.userId,
      orElse: () => <String, dynamic>{},
    );
    if (s.isEmpty) continue;
    final key = '${s['grade']}-${s['class_num']}';
    classMap[key]?.participants.add(c.userId);
  }
  final classPct = <String, double>{
    for (final e in classMap.entries)
      e.key: e.value.students == 0
          ? 0
          : (e.value.participants.length / e.value.students) * 100,
  };

  // Category averages (last 14 days)
  final perCat = <String, List<double>>{};
  for (final c in history) {
    for (final entry in c.categoryScores.entries) {
      perCat.putIfAbsent(entry.key, () => []).add(entry.value);
    }
  }
  final catAvg = <String, double>{
    for (final e in perCat.entries)
      e.key: e.value.reduce((a, b) => a + b) / e.value.length,
  };

  double avgInRange(DateTime start, DateTime endExclusive) {
    final scores = history
        .where((c) =>
            !c.checkinDate.isBefore(start) && c.checkinDate.isBefore(endExclusive))
        .map((c) => c.scorePct);
    return scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;
  }

  final weekStart = KstDate.startOfWeek();
  final lastWeekStart = weekStart.subtract(const Duration(days: 7));

  return SchoolOverview(
    todayParticipationPct: todayPct,
    totalStudents: totalStudents,
    todayParticipants: todayParticipants,
    weeklyAvg: avgInRange(weekStart, weekStart.add(const Duration(days: 7))),
    lastWeekAvg: avgInRange(lastWeekStart, weekStart),
    last14Days: last14,
    classParticipation: classPct,
    categoryAverages: catAvg,
  );
});

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

final classStatsProvider =
    FutureProvider.family<ClassStats, String>((ref, classKey) async {
  final parts = classKey.split('-');
  final grade = int.tryParse(parts[0]);
  final classNum = parts.length > 1 ? int.tryParse(parts[1]) : null;
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) {
    return ClassStats(
      classKey: classKey,
      studentCount: 0,
      participationByDay: const [],
      categoryAverages: const {},
      weakestRules: const [],
      nonParticipantsToday: const [],
    );
  }

  final schoolId = profile!.schoolId!;
  final allStudents = await ref.read(schoolStudentsProvider.future);
  final classStudents = allStudents
      .where((s) => s['grade'] == grade && s['class_num'] == classNum)
      .toList();
  final classUserIds = classStudents.map((s) => s['user_id'] as String).toSet();

  final repo = ref.read(checkinRepositoryProvider);
  final history = (await repo.fetchSchoolHistory(schoolId: schoolId, days: 14))
      .where((c) => classUserIds.contains(c.userId))
      .toList();
  final rules = await ref.read(schoolRulesProvider.future);

  final today = KstDate.today();
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final byDay = <({DateTime date, int participants, int total})>[];
  for (var i = 13; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final p = history
        .where((c) => same(c.checkinDate, d))
        .map((c) => c.userId)
        .toSet()
        .length;
    byDay.add((date: d, participants: p, total: classStudents.length));
  }

  // Category avgs
  final perCat = <String, List<double>>{};
  for (final c in history) {
    for (final e in c.categoryScores.entries) {
      perCat.putIfAbsent(e.key, () => []).add(e.value);
    }
  }
  final catAvg = <String, double>{
    for (final e in perCat.entries)
      e.key: e.value.reduce((a, b) => a + b) / e.value.length,
  };

  // Weakest rules
  final perRule = <String, List<int>>{};
  for (final c in history) {
    for (final e in c.answers.entries) {
      perRule.putIfAbsent(e.key, () => []).add(e.value ? 1 : 0);
    }
  }
  final rates = perRule.entries
      .map((e) => (
            ruleId: e.key,
            text: rules
                .firstWhere(
                  (r) => r.id == e.key,
                  orElse: () => rules.isNotEmpty
                      ? rules.first
                      : throw StateError('no rule'),
                )
                .ruleText,
            avgOk: e.value.reduce((a, b) => a + b) / e.value.length,
          ))
      .toList()
    ..sort((a, b) => a.avgOk.compareTo(b.avgOk));

  // Today non-participants
  final participantsToday = history
      .where((c) => same(c.checkinDate, today))
      .map((c) => c.userId)
      .toSet();
  final nonP = classStudents
      .where((s) => !participantsToday.contains(s['user_id']))
      .map((s) => (
            nickname: s['nickname'] as String,
            grade: (s['grade'] as int?) ?? 0,
            classNum: (s['class_num'] as int?) ?? 0,
            studentNum: (s['student_num'] as int?) ?? 0,
          ))
      .toList();

  return ClassStats(
    classKey: classKey,
    studentCount: classStudents.length,
    participationByDay: byDay,
    categoryAverages: catAvg,
    weakestRules: rates.take(3).toList(),
    nonParticipantsToday: nonP,
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

final studentRowsProvider = FutureProvider<List<StudentRow>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final schoolId = profile!.schoolId!;
  final students = await ref.read(schoolStudentsProvider.future);
  final repo = ref.read(checkinRepositoryProvider);
  final history = await repo.fetchSchoolHistory(schoolId: schoolId, days: 60);

  final badges = await _fetchBadgeCounts(
    students.map((s) => s['user_id'] as String).toList(),
  );

  final rows = <StudentRow>[];
  final today = KstDate.today();
  for (final s in students) {
    final uid = s['user_id'] as String;
    final mine = history.where((c) => c.userId == uid).toList()
      ..sort((a, b) => b.checkinDate.compareTo(a.checkinDate));
    final lastDate = mine.isEmpty ? null : mine.first.checkinDate;
    final avg = mine.isEmpty
        ? 0.0
        : mine.map((c) => c.scorePct).reduce((a, b) => a + b) / mine.length;
    final missed =
        lastDate == null ? 999 : today.difference(lastDate).inDays;
    rows.add(StudentRow(
      userId: uid,
      profileId: s['id'] as String,
      nickname: s['nickname'] as String,
      grade: (s['grade'] as int?) ?? 0,
      classNum: (s['class_num'] as int?) ?? 0,
      studentNum: (s['student_num'] as int?) ?? 0,
      streak: _streakForUser(history, uid),
      lastCheckinDate: lastDate,
      avgScore: avg,
      badgeCount: badges[uid] ?? 0,
      missedDays: missed < 0 ? 0 : missed,
    ));
  }
  return rows;
});

int _streakForUser(List<DailyCheckin> history, String userId) {
  final mine = history.where((c) => c.userId == userId).toList();
  if (mine.isEmpty) return 0;
  final dates = mine
      .map((c) => DateTime(c.checkinDate.year, c.checkinDate.month, c.checkinDate.day))
      .toSet();
  var probe = KstDate.today();
  if (!dates.contains(probe)) {
    probe = probe.subtract(const Duration(days: 1));
    if (!dates.contains(probe)) return 0;
  }
  var streak = 0;
  while (dates.contains(probe)) {
    streak++;
    probe = probe.subtract(const Duration(days: 1));
  }
  return streak;
}

Future<Map<String, int>> _fetchBadgeCounts(List<String> userIds) async {
  if (userIds.isEmpty) return {};
  final rows = await SupabaseService.client
      .from('user_badges')
      .select('user_id')
      .inFilter('user_id', userIds);
  final counts = <String, int>{};
  for (final r in rows) {
    final uid = r['user_id'] as String;
    counts[uid] = (counts[uid] ?? 0) + 1;
  }
  return counts;
}
