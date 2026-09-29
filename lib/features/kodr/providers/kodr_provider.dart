import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/kodr_repository.dart';
import '../models/kodr.dart';

final kodrRepositoryProvider =
    Provider<KodrRepository>((_) => KodrRepository());

/// 이번 달 K-ODR 집계 (가입하지 않은 학생 포함).
final kodrSummaryProvider = FutureProvider<List<KodrSummaryEntry>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(kodrRepositoryProvider).monthSubjects();
});

/// K-ODR 에서 고를 수 있는 학생 — 명렬표 전체.
/// 예전에는 가입한 학생만 나와서, 가입하지 않은 학생은 기록할 수 없었다.
final kodrStudentOptionsProvider =
    FutureProvider.autoDispose<List<KodrStudentOption>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(kodrRepositoryProvider).studentOptions();
});
