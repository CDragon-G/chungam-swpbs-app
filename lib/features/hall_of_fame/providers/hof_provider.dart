import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/providers/profile_provider.dart';
import '../models/hof_entry.dart';

/// 이번 달 명예의 전당 (학교 기준).
final hallOfFameProvider = FutureProvider<List<HofEntry>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final rows = await SupabaseService.client.rpc('hall_of_fame', params: {
    'p_school_id': profile!.schoolId,
  });
  return List<Map<String, dynamic>>.from(rows as List)
      .map(HofEntry.fromMap)
      .toList();
});
