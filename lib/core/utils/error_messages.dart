import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates Supabase / network / app errors into user-friendly Korean.
/// Use this in every catch block before displaying to the user.
String translateError(Object error) {
  // Always log the raw error for debugging (visible in `flutter run` console).
  debugPrint('[translateError] raw=$error  type=${error.runtimeType}');
  if (error is AuthException) {
    debugPrint(
        '[translateError] AuthException code=${_safeCode(error)} msg=${error.message} status=${error.statusCode}');
  }
  if (error is PostgrestException) {
    debugPrint(
        '[translateError] PostgrestException code=${error.code} msg=${error.message} details=${error.details}');
  }

  // ── Supabase Auth ────────────────────────────────────────────
  if (error is AuthException) {
    // newer SDK exposes a `code` field on AuthApiException
    final code = _safeCode(error);
    final byCode = _authMessageByCode(code);
    if (byCode != null) return byCode;
    return _authMessageByText(error.message);
  }

  // ── Supabase DB / RLS ────────────────────────────────────────
  if (error is PostgrestException) {
    final c = error.code;
    // P0001 = RPC 내부 raise exception → 우리가 작성한 한글 메시지를 그대로 노출
    if (c == 'P0001' && error.message.trim().isNotEmpty) return error.message;
    if (c == '42501') return '권한이 없어요. 다시 로그인 후 시도해주세요.';
    if (c == '23505') return '이미 존재하는 데이터예요.';
    if (c == '23503') return '연결된 정보가 없어 처리할 수 없어요.';
    if (c == '54001') return '서버 설정 오류입니다. 관리자에게 문의해주세요.';
    if (error.message.toLowerCase().contains('row-level security')) {
      return '권한이 없어요. 다시 로그인 후 시도해주세요.';
    }
    return '데이터 처리 중 오류가 발생했어요.';
  }

  // ── Network / generic ────────────────────────────────────────
  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('handshakeexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('network is unreachable')) {
    return '인터넷 연결을 확인해주세요.';
  }
  if (raw.contains('timeout')) {
    return '응답이 너무 늦어요. 잠시 후 다시 시도해주세요.';
  }

  // App-thrown StateError (my own validations)
  if (error is StateError) {
    return error.message;
  }

  return '오류가 발생했어요. 잠시 후 다시 시도해주세요.';
}

String? _safeCode(AuthException e) {
  try {
    final dyn = e as dynamic;
    final c = dyn.code;
    if (c is String) return c;
  } catch (_) {}
  return null;
}

String? _authMessageByCode(String? code) {
  if (code == null) return null;
  switch (code) {
    case 'user_already_exists':
    case 'email_address_already_in_use':
      return '이미 등록된 이메일이에요. 로그인해주세요.';
    case 'invalid_credentials':
    case 'invalid_grant':
      return '이메일 또는 비밀번호가 올바르지 않아요.';
    case 'weak_password':
      return '비밀번호가 너무 약해요. 6자 이상 입력해주세요.';
    case 'email_not_confirmed':
      return '이메일 인증이 필요해요. 받은 메일을 확인해주세요.';
    case 'signup_disabled':
      return '현재 회원가입이 잠시 중단되었어요.';
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return '너무 많이 시도했어요. 잠시 후 다시 시도해주세요.';
    case 'user_not_found':
      return '등록되지 않은 이메일이에요.';
    case 'session_expired':
      return '로그인 세션이 만료됐어요. 다시 로그인해주세요.';
    default:
      return null;
  }
}

String _authMessageByText(String message) {
  final m = message.toLowerCase();
  if (m.contains('already registered') ||
      m.contains('already in use') ||
      m.contains('user_already_exists') ||
      m.contains('user with this email already exists') ||
      m.contains('email address is already')) {
    return '이미 등록된 이메일이에요. 로그인해주세요.';
  }
  if (m.contains('invalid login credentials') ||
      m.contains('invalid credentials') ||
      m.contains('invalid grant')) {
    return '이메일 또는 비밀번호가 올바르지 않아요.';
  }
  if (m.contains('weak password') ||
      m.contains('password should be') ||
      m.contains('password is too short')) {
    return '비밀번호가 너무 약해요. 6자 이상 입력해주세요.';
  }
  if (m.contains('email not confirmed') ||
      m.contains('email_not_confirmed')) {
    return '이메일 인증이 필요해요.';
  }
  if (m.contains('signup is disabled') ||
      m.contains('signups not allowed')) {
    return '현재 회원가입이 일시 중지되었어요.';
  }
  if (m.contains('rate limit') ||
      m.contains('too many') ||
      m.contains('email rate limit')) {
    return '너무 많이 시도했어요. 잠시 후(보통 1시간) 다시 시도해주세요.';
  }
  if (m.contains('not found')) {
    return '등록되지 않은 사용자예요.';
  }
  if (m.contains('invalid email') ||
      m.contains('invalid format')) {
    return '이메일 형식이 올바르지 않아요.';
  }
  if (m.contains('database error') ||
      m.contains('saving new user') ||
      m.contains('could not save')) {
    return '서버에서 사용자 정보를 저장하지 못했어요.\n이미 같은 이메일이 가입되어 있을 수 있어요.';
  }
  if (m.contains('captcha')) {
    return '인증 보안 검사를 통과하지 못했어요. 다시 시도해주세요.';
  }
  // Surface unknown error message for debugging — visible only to testers
  // since release shouldn't trigger unknown paths often
  return '회원가입 중 오류가 발생했어요.\n원인: ${message.length > 100 ? message.substring(0, 100) : message}';
}
