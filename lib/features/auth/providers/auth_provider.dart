import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

/// Emits current Supabase User (null when signed out).
final authStateProvider = StreamProvider<User?>((ref) async* {
  final initial = SupabaseService.auth.currentUser;
  yield initial;
  await for (final event in SupabaseService.auth.onAuthStateChange) {
    yield event.session?.user;
  }
});
