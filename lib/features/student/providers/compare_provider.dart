import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../school/providers/school_provider.dart';

class CompareStats {
  CompareStats({
    required this.myAvg,
    required this.classAvg,
    required this.gradeAvg,
    required this.schoolAvg,
    required this.percentile,
    required this.anonymousRanking,
    required this.myRank,
  });

  final double myAvg;
  final double classAvg;
  final double gradeAvg;
  final double schoolAvg;
  final int percentile;
  final List<({String label, double score, bool isMe})> anonymousRanking;
  final int myRank;
}

final compareStatsProvider = FutureProvider<CompareStats>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile.schoolId == null) {
    return CompareStats(
      myAvg: 0,
      classAvg: 0,
      gradeAvg: 0,
      schoolAvg: 0,
      percentile: 100,
      anonymousRanking: const [],
      myRank: 0,
    );
  }

  final client = SupabaseService.client;
  final since = KstDate.formatYmd(
    KstDate.today().subtract(const Duration(days: 29)),
  );

  // 1. Fetch all check-ins for the school in the last 30 days.
  final checkRows = await client
      .from('daily_checkins')
      .select('user_id, score_pct')
      .eq('school_id', profile.schoolId!)
      .gte('checkin_date', since);

  // 2. Fetch all student profiles for the same school (with class info).
  final students = await ref.read(schoolStudentsProvider.future);
  final classByUser = <String, ({int? grade, int? classNum})>{
    for (final s in students)
      s['user_id'] as String: (
        grade: s['grade'] as int?,
        classNum: s['class_num'] as int?,
      ),
  };

  final perUser = <String, List<double>>{};
  for (final r in checkRows) {
    final uid = r['user_id'] as String;
    final score = (r['score_pct'] as num).toDouble();
    perUser.putIfAbsent(uid, () => []).add(score);
  }

  double avg(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  final myUserId = SupabaseService.auth.currentUser?.id;
  final myAvg = avg(perUser[myUserId] ?? []);

  final classScores = <double>[];
  final gradeScores = <double>[];
  final schoolScores = <double>[];
  perUser.forEach((uid, scores) {
    final a = avg(scores);
    schoolScores.add(a);
    final meta = classByUser[uid];
    if (meta == null) return;
    if (meta.grade == profile.grade) gradeScores.add(a);
    if (meta.grade == profile.grade && meta.classNum == profile.classNum) {
      classScores.add(a);
    }
  });

  // Percentile: rank highest first
  final sortedDesc = [...schoolScores]..sort((a, b) => b.compareTo(a));
  final myRank = sortedDesc.indexWhere((s) => s == myAvg) + 1;
  final pct = sortedDesc.isEmpty
      ? 100
      : ((myRank / sortedDesc.length) * 100).clamp(1, 100).round();

  // Anonymous class ranking
  final classEntries = perUser.entries
      .where((e) {
        final m = classByUser[e.key];
        return m != null &&
            m.grade == profile.grade &&
            m.classNum == profile.classNum;
      })
      .toList()
    ..sort((a, b) => avg(b.value).compareTo(avg(a.value)));

  var counter = 1;
  final classRanking = <({String label, double score, bool isMe})>[];
  for (final e in classEntries) {
    final isMe = e.key == myUserId;
    classRanking.add((
      label: isMe ? '나' : '학생 ${counter++}',
      score: avg(e.value),
      isMe: isMe,
    ));
  }

  return CompareStats(
    myAvg: myAvg,
    classAvg: avg(classScores),
    gradeAvg: avg(gradeScores),
    schoolAvg: avg(schoolScores),
    percentile: pct,
    anonymousRanking: classRanking,
    myRank: myRank,
  );
});
