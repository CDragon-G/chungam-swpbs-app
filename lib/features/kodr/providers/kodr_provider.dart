import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/kodr_repository.dart';
import '../models/kodr.dart';

final kodrRepositoryProvider =
    Provider<KodrRepository>((_) => KodrRepository());

/// 현황에서 보고 있는 기간. 처음에는 이번 달.
final kodrPeriodProvider =
    StateProvider<KodrPeriod>((_) => KodrPeriod.thisMonth());

/// 고른 기간의 K-ODR 현황 (가입하지 않은 학생 포함).
final kodrSummaryProvider = FutureProvider<KodrPeriodSummary>((ref) async {
  final profile = ref.watch(profileProvider).value;
  final period = ref.watch(kodrPeriodProvider);
  if (profile?.schoolId == null) {
    return const KodrPeriodSummary(items: [], months: [], total: 0);
  }
  return ref.read(kodrRepositoryProvider).periodSubjects(period);
});

/// 한 학생의 누적 이력.
final kodrHistoryProvider =
    FutureProvider.autoDispose.family<KodrHistory, String>((ref, subjectId) {
  return ref.read(kodrRepositoryProvider).subjectHistory(subjectId);
});

/// K-ODR 에서 고를 수 있는 학생 — 명렬표 전체.
/// 예전에는 가입한 학생만 나와서, 가입하지 않은 학생은 기록할 수 없었다.
final kodrStudentOptionsProvider =
    FutureProvider.autoDispose<List<KodrStudentOption>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(kodrRepositoryProvider).studentOptions();
});
