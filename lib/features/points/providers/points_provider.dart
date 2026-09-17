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

final myExchangesProvider = FutureProvider<List<PointExchange>>((ref) async {
  ref.watch(profileProvider);
  return ref.read(pointsRepositoryProvider).myExchanges();
});

// ── Teacher-side ─────────────────────────────────────────────
final allStoreItemsProvider = FutureProvider<List<PointStoreItem>>((ref) async {
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

final allExchangesProvider = FutureProvider<List<PointExchange>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref
      .read(pointsRepositoryProvider)
      .fetchSchoolExchanges(profile!.schoolId!);
});

/// 교환 요청 검색어 해석.
///   "김민"        → 이름에 '김민' 포함
///   "2-3"         → 2학년 3반 (2 3, 2학년 3반 도 같음)
///   "2-3-15"      → 2학년 3반 15번
///   "20315"       → 학번 (2학년 03반 15번), 4자리면 2315
typedef ExchangeQuery = ({String? name, int? grade, int? classNum, int? num});

ExchangeQuery? parseExchangeQuery(String raw) {
  final q = raw.trim();
  if (q.isEmpty) return null;
  final nums = RegExp(r'\d+').allMatches(q).map((m) => m.group(0)!).toList();
  final letters = q.replaceAll(RegExp(r'[\d\s\-./학년반번]'), '');
  if (letters.isEmpty && nums.isNotEmpty) {
    if (nums.length == 1 && (nums[0].length == 4 || nums[0].length == 5)) {
      final d = nums[0];
      final c = d.length == 5 ? d.substring(1, 3) : d.substring(1, 2);
      return (
        name: null,
        grade: int.parse(d[0]),
        classNum: int.parse(c),
        num: int.parse(d.substring(d.length - 2)),
      );
    }
    return (
      name: null,
      grade: int.parse(nums[0]),
      classNum: nums.length > 1 ? int.parse(nums[1]) : null,
      num: nums.length > 2 ? int.parse(nums[2]) : null,
    );
  }
  return (name: q, grade: null, classNum: null, num: null);
}

final exchangeSearchProvider = FutureProvider.autoDispose
    .family<List<PointExchange>, String>((ref, raw) async {
  final profile = ref.watch(profileProvider).value;
  final q = parseExchangeQuery(raw);
  if (profile?.schoolId == null || q == null) return [];
  return ref.read(pointsRepositoryProvider).searchSchoolExchanges(
        profile!.schoolId!,
        nickname: q.name,
        grade: q.grade,
        classNum: q.classNum,
        studentNum: q.num,
      );
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
final pointEconomyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await SupabaseService.client.rpc('point_economy_stats');
  return Map<String, dynamic>.from(res as Map);
});

/// 우리 반 포인트 현황 — 담임 선생님용.
/// 프로필에 학년·반이 없으면 ok:false 로 돌아온다.
final classPointEconomyProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await SupabaseService.client.rpc('class_point_economy_stats');
  return Map<String, dynamic>.from(res as Map);
});
