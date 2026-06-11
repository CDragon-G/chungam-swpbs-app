import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/points_repository.dart';
import '../models/point_exchange.dart';
import '../models/point_store_item.dart';
import '../models/point_transaction.dart';
import '../models/school_leaderboard_entry.dart';

final pointsRepositoryProvider =
    Provider<PointsRepository>((_) => PointsRepository());

// ── Student-side ─────────────────────────────────────────────
final myPointsProvider = FutureProvider<int>((ref) async {
  ref.watch(profileProvider);
  return ref.read(pointsRepositoryProvider).myBalance();
});

final myPointsHistoryProvider =
    FutureProvider<List<PointTransaction>>((ref) async {
  ref.watch(profileProvider);
  return ref.read(pointsRepositoryProvider).myHistory(limit: 100);
});

final activeStoreItemsProvider =
    FutureProvider<List<PointStoreItem>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref
      .read(pointsRepositoryProvider)
      .fetchItems(profile!.schoolId!, onlyActive: true);
});

final myExchangesProvider =
    FutureProvider<List<PointExchange>>((ref) async {
  ref.watch(profileProvider);
  return ref.read(pointsRepositoryProvider).myExchanges();
});

// ── Teacher-side ─────────────────────────────────────────────
final allStoreItemsProvider =
    FutureProvider<List<PointStoreItem>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(pointsRepositoryProvider).fetchItems(profile!.schoolId!);
});

final pendingExchangesProvider =
    FutureProvider<List<PointExchange>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref
      .read(pointsRepositoryProvider)
      .fetchSchoolExchanges(profile!.schoolId!, status: 'pending');
});

final allExchangesProvider =
    FutureProvider<List<PointExchange>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref
      .read(pointsRepositoryProvider)
      .fetchSchoolExchanges(profile!.schoolId!);
});

// ── School Leaderboard (national) ────────────────────────────
final schoolLeaderboardProvider =
    FutureProvider<List<SchoolLeaderboardEntry>>((ref) async {
  return ref.read(pointsRepositoryProvider).fetchLeaderboard(limit: 100);
});

final mySchoolEntryProvider =
    FutureProvider<SchoolLeaderboardEntry?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return null;
  return ref.read(pointsRepositoryProvider).fetchMySchool(profile!.schoolId!);
});
