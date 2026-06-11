import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/checkin_repository.dart';
import '../models/daily_checkin.dart';

final checkinRepositoryProvider =
    Provider<CheckinRepository>((_) => CheckinRepository());

final todayCheckinProvider = FutureProvider<DailyCheckin?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return null;
  final repo = ref.read(checkinRepositoryProvider);
  return repo.fetchToday(profile!.schoolId!);
});

final checkinHistoryProvider =
    FutureProvider.family<List<DailyCheckin>, int>((ref, days) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(checkinRepositoryProvider);
  return repo.fetchHistory(days: days);
});

/// In-progress answers being collected on the check-in screen.
/// Map<ruleId, bool?>  — null = not answered yet.
final checkinAnswersProvider =
    StateProvider<Map<String, bool?>>((_) => <String, bool?>{});

final checkinCommentProvider = StateProvider<String>((_) => '');
