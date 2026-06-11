import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/models/badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../checkin/models/daily_checkin.dart';
import '../../checkin/providers/checkin_provider.dart';
import 'student_stats_provider.dart';

final allBadgesProvider = FutureProvider<List<BadgeDef>>((ref) async {
  final rows = await SupabaseService.client.from('badges').select().order('condition_value');
  return rows.map((m) => BadgeDef.fromMap(m as Map<String, dynamic>)).toList();
});

final userBadgesProvider = FutureProvider<List<UserBadge>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final rows = await SupabaseService.client
      .from('user_badges')
      .select()
      .eq('user_id', user.id);
  return rows.map((m) => UserBadge.fromMap(m as Map<String, dynamic>)).toList();
});

/// Evaluate all badge conditions and award missing badges.
/// Returns the badge defs newly awarded. Accepts both `Ref` and `WidgetRef`
/// so it can be called from providers or widgets.
Future<List<BadgeDef>> evaluateAndAwardBadges(WidgetRef ref) async {
  final user = SupabaseService.auth.currentUser;
  if (user == null) return [];
  final badges = await ref.read(allBadgesProvider.future);
  final alreadyOwned = (await ref.read(userBadgesProvider.future))
      .map((b) => b.badgeId)
      .toSet();

  final history = await ref.read(checkinHistoryProvider(60).future);
  final total = await ref.read(checkinRepositoryProvider).totalCount();
  final streak = calculateStreak(history);
  final todayMax = history.isEmpty ? 0 : history.first.scorePct.round();
  final hasFullWeek = _hasFullWeek(history);

  final newly = <BadgeDef>[];
  for (final b in badges) {
    if (alreadyOwned.contains(b.id)) continue;
    final earned = _earned(b, total, streak, todayMax, hasFullWeek);
    if (!earned) continue;
    try {
      await SupabaseService.client.from('user_badges').insert({
        'user_id': user.id,
        'badge_id': b.id,
      });
      newly.add(b);
    } catch (_) {
      // unique violation = already awarded; ignore
    }
  }
  if (newly.isNotEmpty) {
    ref.invalidate(userBadgesProvider);
  }
  return newly;
}

bool _earned(
  BadgeDef b,
  int total,
  int streak,
  int todayMax,
  bool hasFullWeek,
) {
  switch (b.conditionType) {
    case 'first_checkin':
      return total >= 1;
    case 'streak_3':
      return streak >= 3;
    case 'streak_7':
      return streak >= 7;
    case 'streak_30':
      return streak >= 30;
    case 'perfect_score':
      return todayMax >= 100;
    case 'full_week':
      return hasFullWeek;
    case 'total_checkins':
      return total >= b.conditionValue;
    default:
      return false;
  }
}

/// Mon~Fri of the current KST week all have check-ins.
bool _hasFullWeek(List<DailyCheckin> ch) {
  final monday = KstDate.startOfWeek();
  final wanted = List.generate(5, (i) => monday.add(Duration(days: i)));
  final have = ch
      .map((c) => DateTime(c.checkinDate.year, c.checkinDate.month, c.checkinDate.day))
      .toSet();
  return wanted.every(have.contains);
}
