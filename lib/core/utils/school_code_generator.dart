import 'dart:math';

class SchoolCodeGenerator {
  SchoolCodeGenerator._();

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
