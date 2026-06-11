import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/profile.dart';

class AuthRepository {
  AuthRepository();

  SupabaseClient get _c => SupabaseService.client;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) =>
      _c.auth.signUp(email: email, password: password);

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _c.auth.signOut();

  /// Create the profile row matching the current auth user.
  Future<Profile> createProfile({
    required String role,
    required String nickname,
    String? schoolId,
    int? grade,
    int? classNum,
    int? studentNum,
    String? teacherRole, // 'admin' | 'regular' for teachers
  }) async {
    final user = _c.auth.currentUser;
    if (user == null) {
      throw StateError('로그인 상태가 아닙니다.');
    }
    final inserted = await _c
        .from('profiles')
        .insert({
          'user_id': user.id,
          'role': role,
          'nickname': nickname,
          if (schoolId != null) 'school_id': schoolId,
          if (grade != null) 'grade': grade,
          if (classNum != null) 'class_num': classNum,
          if (studentNum != null) 'student_num': studentNum,
          if (teacherRole != null) 'teacher_role': teacherRole,
        })
        .select()
        .single();
    return Profile.fromMap(inserted);
  }

  Future<Profile?> fetchMyProfile() async {
    final user = _c.auth.currentUser;
    if (user == null) return null;
    final row = await _c
        .from('profiles')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<Profile> updateProfile(Map<String, dynamic> patch) async {
    final user = _c.auth.currentUser;
    if (user == null) throw StateError('로그인 상태가 아닙니다.');
    final row = await _c
        .from('profiles')
        .update(patch)
        .eq('user_id', user.id)
        .select()
        .single();
    return Profile.fromMap(row);
  }

  Stream<AuthState> authStateChanges() => _c.auth.onAuthStateChange;

  User? get currentUser => _c.auth.currentUser;
}
