import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/cico_repository.dart';
import '../models/cico.dart';

final cicoRepositoryProvider = Provider<CicoRepository>((_) => CicoRepository());

/// 교사: 우리 학교의 진행 중 CICO 목록.
final cicoEnrollmentsProvider =
    FutureProvider<List<CicoEnrollment>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(cicoRepositoryProvider).listForSchool(profile!.schoolId!);
});

/// 학생: 내 진행 중 CICO (없으면 null).
final myCicoProvider = FutureProvider<CicoEnrollment?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile.role != 'student') return null;
  return ref.read(cicoRepositoryProvider).myActiveEnrollment();
});

/// 특정 등록의 진전도 이력 (그래프용).
final cicoHistoryProvider = FutureProvider.autoDispose
    .family<List<CicoDaily>, String>((ref, enrollmentId) async {
  return ref.read(cicoRepositoryProvider).history(enrollmentId);
});


/// CICO 시작 권장 후보 — 이달 K-ODR이 학교 기준 이상 & CICO 미진행.
/// (threshold는 각 행에 함께 담겨 옴)
final cicoCandidatesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await SupabaseService.client.rpc('cico_candidates');
  return List<Map<String, dynamic>>.from(rows as List);
});
