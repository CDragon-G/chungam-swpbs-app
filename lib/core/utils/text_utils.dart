import 'package:flutter/widgets.dart';

/// 한국어 줄바꿈 보정.
///
/// Flutter는 한국어를 글자 단위로 줄바꿈해 어절이 중간에서 끊긴다
/// (예: "학생과" → "학생" / "과"). 어절 내부 글자 사이에
/// 워드조이너(U+2060)를 삽입하면 공백에서만 줄바꿈되어
/// CSS의 `word-break: keep-all`처럼 자연스럽게 읽힌다.
///
/// 이모지 등 복합 문자가 깨지지 않도록 grapheme(characters) 단위로 처리.
extension WordSafeText on String {
  static const _wordJoiner = '⁠';

  String get wordSafe =>
      split(' ').map((w) => w.characters.join(_wordJoiner)).join(' ');
}
