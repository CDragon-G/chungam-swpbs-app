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

  /// 가입을 시도하되, 이미 존재하는 이메일이면 로그인으로 복구한다.
  /// - 신규 이메일: 가입 + 로그인 → 프로필 생성 단계로 진행
  /// - 고아 계정(가입만 되고 프로필 없음): 로그인 → 프로필 생성 단계로 진행
  /// - 이미 완성된 계정: 안내 메시지와 함께 중단(StateError)
  /// - 비밀번호 불일치: 안내 메시지와 함께 중단(StateError)
  Future<void> signUpOrRecover({
    required String email,
    required String password,
  }) async {
    try {
      await _c.auth.signUp(email: email, password: password);
      // 가입 성공 → 로그인 시도 (Confirm email OFF면 즉시 로그인됨)
      try {
        await _c.auth.signInWithPassword(email: email, password: password);
      } catch (_) {/* 세션은 createProfile 전 다시 확인 */}
      return;
    } on AuthException catch (e) {
      if (!_isAlreadyExists(e)) rethrow;
      // 이미 존재하는 이메일 → 로그인으로 복구 시도
      try {
        await _c.auth.signInWithPassword(email: email, password: password);
      } on AuthException {
        throw StateError(
          '이미 가입된 이메일이에요.\n'
          '비밀번호가 맞으면 로그인 화면을 이용하시고,\n'
          '비밀번호가 기억나지 않으면 담당 선생님께 초기화를 요청하세요.',
        );
      }
      // 로그인 성공 → 프로필이 이미 있으면 완성된 계정
      final existing = await fetchMyProfile();
      if (existing != null) {
        throw StateError('이미 가입이 완료된 계정이에요. 로그인 화면을 이용해주세요.');
      }
      // 프로필 없음 = 고아 계정 → 프로필 생성 단계로 진행
      return;
    }
  }

  bool _isAlreadyExists(AuthException e) {
    final code = (() {
      try {
        final c = (e as dynamic).code;
        return c is String ? c : null;
      } catch (_) {
        return null;
      }
    })();
    if (code == 'user_already_exists' ||
        code == 'email_address_already_in_use') {
      return true;
    }
    final m = e.message.toLowerCase();
    return m.contains('already registered') ||
        m.contains('already in use') ||
        m.contains('user with this email already exists') ||
        m.contains('email address is already');
  }

  /// 교사가 같은 학교 학생의 비밀번호를 임시 비번으로 초기화한다.
  /// 서버 RPC(reset_student_password)가 권한·소속을 검증한다.
  Future<void> resetStudentPassword({
    required String profileId,
    required String newPassword,
  }) async {
    await _c.rpc('reset_student_password', params: {
      'p_profile_id': profileId,
      'p_new_password': newPassword,
    });
  }

  Future<void> signOut() => _c.auth.signOut();

  /// 계정 완전 삭제 (Apple Guideline 5.1.1 대응).
  /// Supabase RPC가 auth.users를 삭제하면 CASCADE로 모든 사용자 데이터가 제거됨.
  /// 삭제 후 로컬 세션도 정리.
  Future<void> deleteAccount() async {
    final user = _c.auth.currentUser;
    if (user == null) throw StateError('로그인 상태가 아닙니다.');
    await _c.rpc('delete_my_account');
    await _c.auth.signOut();
  }

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
