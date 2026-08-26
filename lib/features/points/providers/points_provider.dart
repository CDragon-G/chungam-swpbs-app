import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

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
  // 학생: 전교 공통 + 우리 반 상품만. (교사가 미리보기로 봐도 동일 로직)
  return ref.read(pointsRepositoryProvider).fetchItemsForStudent(
        schoolId: profile!.schoolId!,
        grade: profile.grade,
        classNum: profile.classNum,
      );
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


/// 🪙 우리 학교 포인트 경제 통계 (관리자용 — 인플레이션 점검).
final pointEconomyProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await SupabaseService.client.rpc('point_economy_stats');
  return Map<String, dynamic>.from(res as Map);
});

/// 우리 반 포인트 현황 — 담임 선생님용.
/// 프로필에 학년·반이 없으면 ok:false 로 돌아온다.
final classPointEconomyProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final res =
      await SupabaseService.client.rpc('class_point_economy_stats');
  return Map<String, dynamic>.from(res as Map);
});
