import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/kodr_repository.dart';
import '../models/kodr.dart';

final kodrRepositoryProvider = Provider<KodrRepository>((_) => KodrRepository());

/// 이번 달 K-ODR 집계 (교사 학교 기준).
final kodrSummaryProvider =
    FutureProvider<List<KodrSummaryEntry>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref
      .read(kodrRepositoryProvider)
      .monthlySummary(profile!.schoolId!);
});
