import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../models/profile.dart';

/// Fetches the current user's profile row (null if not yet created).
final profileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final repo = ref.read(authRepositoryProvider);
  return repo.fetchMyProfile();
});
