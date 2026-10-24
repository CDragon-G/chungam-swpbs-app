import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/core/review/review_prompt.dart';

void main() {
  final now = DateTime(2026, 11, 20);
  bool ask({
    bool teacher = false,
    int happy = 10,
    int usedDays = 30,
    int? askedDaysAgo,
    int asks = 0,
  }) =>
      ReviewPrompt.shouldAsk(
        teacher: teacher,
        happy: happy,
        firstSeen: now.subtract(Duration(days: usedDays)),
        lastAsked: askedDaysAgo == null
            ? null
            : now.subtract(Duration(days: askedDaysAgo)),
        asks: asks,
        now: now,
      );

  test('기분 좋은 순간이 쌓이고 2주가 지나면 묻는다', () {
    expect(ask(), isTrue);
    expect(ask(teacher: true, happy: 5), isTrue);
  });

  test('쓴 지 2주가 안 됐으면 묻지 않는다', () {
    expect(ask(usedDays: 13), isFalse);
  });

  test('학생은 10번, 선생님은 5번 쌓여야 한다', () {
    expect(ask(happy: 9), isFalse);
    expect(ask(teacher: true, happy: 4), isFalse);
  });

  test('한 번 물었으면 120일 동안 다시 묻지 않고, 모두 3번까지만', () {
    expect(ask(askedDaysAgo: 119, asks: 1), isFalse);
    expect(ask(askedDaysAgo: 120, asks: 1), isTrue);
    expect(ask(askedDaysAgo: 400, asks: 3), isFalse);
  });
}
