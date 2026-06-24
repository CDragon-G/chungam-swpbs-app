import 'dart:math';

import '../supabase/supabase_client.dart';

class SchoolCodeGenerator {
  SchoolCodeGenerator._();

  static const String _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Format: 2 uppercase letters + 4 digits (e.g. "CH2026").
  static String _generate() {
    final r = Random.secure();
    final l1 = _letters[r.nextInt(_letters.length)];
    final l2 = _letters[r.nextInt(_letters.length)];
    final n = r.nextInt(9000) + 1000;
    return '$l1$l2$n';
  }

  /// Generates a unique school_code by checking Supabase. Retries up to 10x.
  static Future<String> generateUnique() async {
    final client = SupabaseService.client;
    for (var i = 0; i < 10; i++) {
      final candidate = _generate();
      final existing = await client
          .from('schools')
          .select('id')
          .eq('school_code', candidate)
          .maybeSingle();
      if (existing == null) return candidate;
    }
    throw StateError('학교 코드 생성에 실패했습니다. 다시 시도해주세요.');
  }

  /// 교사 전용 코드 형식: 8자리 영문대문자+숫자 (학생 코드보다 길고 추측 어렵게).
  /// 예: "K7M2X9PQ"
  static String generateTeacherCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String normalize(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
