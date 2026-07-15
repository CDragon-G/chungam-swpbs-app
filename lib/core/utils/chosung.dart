/// 한글 초성 유틸 — 규칙 초성 퀴즈용.
library;

const _chosungs = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ',
  'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

/// '배드민턴' → 'ㅂㄷㅁㅌ'. 한글이 아닌 글자는 그대로 둔다.
String toChosung(String text) {
  final sb = StringBuffer();
  for (final code in text.runes) {
    if (code >= 0xAC00 && code <= 0xD7A3) {
      sb.write(_chosungs[(code - 0xAC00) ~/ 588]);
    } else {
      sb.writeCharCode(code);
    }
  }
  return sb.toString();
}

/// 퀴즈 키워드 선정 — 서버(quiz_keyword SQL)와 완전히 동일한 규칙:
/// 한글·영숫자 외 문자를 공백으로 바꾸고, 2글자 이상 토큰 중
/// (길이 내림차순, 사전순 오름차순) 첫 번째.
String? quizKeyword(String ruleText) {
  final cleaned = ruleText.replaceAll(RegExp(r'[^가-힣0-9A-Za-z ]'), ' ');
  final tokens =
      cleaned.split(' ').where((t) => t.length >= 2).toList()
        ..sort((a, b) {
          final byLen = b.length.compareTo(a.length);
          return byLen != 0 ? byLen : a.compareTo(b);
        });
  return tokens.isEmpty ? null : tokens.first;
}
