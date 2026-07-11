import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/providers/profile_provider.dart';
import '../models/growth_status.dart';

/// 학교 공동 새싹 성장 상태 — 교사·학생 홈 공용.
final schoolGrowthProvider = FutureProvider<GrowthStatus?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return null;
  final res = await SupabaseService.client.rpc('school_growth');
  return GrowthStatus.fromMap(Map<String, dynamic>.from(res as Map));
});
