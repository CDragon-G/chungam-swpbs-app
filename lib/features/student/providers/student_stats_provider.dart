import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../checkin/models/daily_checkin.dart';
import '../../checkin/providers/checkin_provider.dart';
import '../../school/models/school_rule.dart';
import '../../school/providers/school_provider.dart';

class StudentStats {
  StudentStats({
    required this.streak,
    required this.longestStreak,
    required this.totalCount,
    required this.last30,
    required this.categoryAverages,
    required this.bestRuleText,
    required this.worstRuleText,
    required this.thisWeekAvg,
    required this.lastWeekAvg,
  });

  final int streak;
  final int longestStreak;
  final int totalCount;
  final List<DailyCheckin> last30;
  final Map<String, double> categoryAverages;
  final String? bestRuleText;
  final String? worstRuleText;
  final double thisWeekAvg;
  final double lastWeekAvg;

  double get weekDelta => thisWeekAvg - lastWeekAvg;
}

/// 수업일 기준 연속 참여 (서버 checkin_streaks).
/// 주말·공휴일·휴업일·방학은 건너뛰므로 금요일 → 월요일도 이어진다.
class StreakInfo {
  const StreakInfo({required this.current, required this.best});
  final int current;
  final int best;
}

final myStreakProvider = FutureProvider<StreakInfo?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return null;
  try {
    final res = await SupabaseService.client.rpc('my_streak');
    final m = Map<String, dynamic>.from(res as Map);
    return StreakInfo(
      current: (m['current'] as num?)?.toInt() ?? 0,
      best: (m['best'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return null; // 서버에 아직 063 이 없으면 아래 달력 계산으로
  }
});

/// (예전 방식) 달력 날짜로 센 연속 — 서버 값을 못 받을 때만 쓴다.
/// Returns 0 if no checkins.
/// Streak counts consecutive days back from today (or yesterday if today missed).
int calculateStreak(List<DailyCheckin> checkins) {
  if (checkins.isEmpty) return 0;
  final today = KstDate.today();
  final dates = checkins
      .map((c) =>
          DateTime(c.checkinDate.year, c.checkinDate.month, c.checkinDate.day))
      .toSet();

  var probe = today;
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

int calculateLongestStreak(List<DailyCheckin> checkins) {
  if (checkins.isEmpty) return 0;
  final dates = checkins
      .map((c) =>
          DateTime(c.checkinDate.year, c.checkinDate.month, c.checkinDate.day))
      .toSet()
      .toList()
    ..sort();
  var longest = 1;
  var current = 1;
  for (var i = 1; i < dates.length; i++) {
    if (dates[i].difference(dates[i - 1]).inDays == 1) {
      current++;
      if (current > longest) longest = current;
    } else {
      current = 1;
    }
  }
  return longest;
}

double _avg(Iterable<double> xs) {
  if (xs.isEmpty) return 0;
  return xs.reduce((a, b) => a + b) / xs.length;
}

Map<String, double> _aggregateCategoryAverages(List<DailyCheckin> ch) {
  final perCat = <String, List<double>>{};
  for (final c in ch) {
    for (final e in c.categoryScores.entries) {
      perCat.putIfAbsent(e.key, () => []).add(e.value);
    }
  }
  return {for (final e in perCat.entries) e.key: _avg(e.value)};
}

({String? best, String? worst}) _bestWorstRule(
  List<DailyCheckin> ch,
  List<SchoolRule> rules,
) {
  final perRule = <String, List<int>>{};
  for (final c in ch) {
    for (final e in c.answers.entries) {
      perRule.putIfAbsent(e.key, () => []).add(e.value ? 1 : 0);
    }
  }
  if (perRule.isEmpty) return (best: null, worst: null);
  final rates = {
    for (final e in perRule.entries)
      e.key: e.value.reduce((a, b) => a + b) / e.value.length,
  };
  final sortedAsc = rates.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  String? lookup(String id) => rules
          .firstWhere((r) => r.id == id,
              orElse: () => SchoolRule(
                    id: '',
                    schoolId: '',
                    space: '',
                    category: '',
                    ruleText: '',
                    orderIndex: 0,
                    isActive: false,
                    createdAt: DateTime.now(),
                  ))
          .ruleText
          .isEmpty
      ? null
      : rules.firstWhere((r) => r.id == id).ruleText;
  return (
    best: lookup(sortedAsc.last.key),
    worst: lookup(sortedAsc.first.key),
  );
}

double _avgInRange(
  List<DailyCheckin> ch,
  DateTime start,
  DateTime endExclusive,
) {
  final inRange = ch
      .where((c) =>
          !c.checkinDate.isBefore(start) &&
          c.checkinDate.isBefore(endExclusive))
      .map((c) => c.scorePct);
  return _avg(inRange);
}

final studentStatsProvider = FutureProvider<StudentStats>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) {
    return StudentStats(
      streak: 0,
      longestStreak: 0,
      totalCount: 0,
      last30: const [],
      categoryAverages: const {},
      bestRuleText: null,
      worstRuleText: null,
      thisWeekAvg: 0,
      lastWeekAvg: 0,
    );
  }
  final rules = ref.watch(schoolRulesProvider).value ?? const [];
  // 뱃지 화면과 같은 60일 기록을 나눠 쓴다 (따로 두 번 내려받지 않게)
  final history = await ref.watch(checkinHistoryProvider(60).future);
  final last30 = history.where((c) {
    final cutoff = KstDate.today().subtract(const Duration(days: 29));
    return !c.checkinDate.isBefore(cutoff);
  }).toList();

  final total = await ref.watch(totalCheckinCountProvider.future);
  final streakInfo = await ref.watch(myStreakProvider.future);
  final categoryAverages = _aggregateCategoryAverages(last30);
  final (best: best, worst: worst) = _bestWorstRule(last30, rules);

  final weekStart = KstDate.startOfWeek();
  final lastWeekStart = weekStart.subtract(const Duration(days: 7));
  final thisWeekAvg =
      _avgInRange(history, weekStart, weekStart.add(const Duration(days: 7)));
  final lastWeekAvg = _avgInRange(history, lastWeekStart, weekStart);

  return StudentStats(
    streak: streakInfo?.current ?? calculateStreak(history),
    longestStreak: streakInfo?.best ?? calculateLongestStreak(history),
    totalCount: total,
    last30: last30,
    categoryAverages: categoryAverages,
    bestRuleText: best,
    worstRuleText: worst,
    thisWeekAvg: thisWeekAvg,
    lastWeekAvg: lastWeekAvg,
  );
});
