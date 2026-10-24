import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/features/growth/models/growth_status.dart';

/// 성장 미션 8개를 모두 끝낸 학교 (관문에 걸리지 않게)
List<Map<String, dynamic>> _allMissions() => [
      for (final k in [
        'rules',
        'roster',
        'join',
        'checkin',
        'praise',
        'kodr',
        'cico',
        'vote'
      ])
        {'key': k, 'label': k, 'done': true},
    ];

GrowthStatus _g({
  required int score,
  required int days,
  List<Map<String, dynamic>> boost = const [],
}) =>
    GrowthStatus.fromMap({
      'school_name': '테스트중',
      'score': score,
      'days': days,
      'year_label': '2026학년도',
      'missions': _allMissions(),
      'activity': const {},
      'boost': boost,
    });

void main() {
  group('진행률은 같은 레벨 안에서 줄지 않는다', () {
    test('양분이 차서 날 조건에 걸리는 순간에도 뒷걸음질하지 않는다', () {
      // Lv.7(160점) → Lv.8 은 170점 + 60일. 30일째.
      final before = _g(score: 168, days: 30); // 양분 80%
      final after = _g(score: 171, days: 30); // 양분 가득, 날만 남음
      expect(before.level, 7);
      expect(after.level, 7);
      expect(after.isDayLocked, isTrue);
      expect(after.progressToNext, greaterThanOrEqualTo(before.progressToNext));
    });

    test('점수와 날이 늘면 진행률도 늘거나 그대로다', () {
      var prev = -1.0;
      var prevLevel = 0;
      for (var day = 0; day <= 300; day += 5) {
        for (var score = 150; score <= 240; score += 3) {
          final g = _g(score: score, days: day);
          if (g.level != prevLevel) {
            prevLevel = g.level;
            prev = -1;
          }
          expect(g.progressToNext, greaterThanOrEqualTo(prev - 1e-9),
              reason: 'score=$score day=$day level=${g.level}');
          prev = g.progressToNext;
        }
        prevLevel = 0;
      }
    });
  });

  group('다음 레벨까지 칭찬 몇 번', () {
    test('칭찬 양분으로 채울 수 있으면 칭찬 횟수를 알려준다', () {
      // Lv.3(40점) → Lv.4(70점): 3점 남음. 칭찬 10번에 1점, 지금 4번 쌓여 있음
      final g = _g(score: 67, days: 10, boost: [
        {'key': 'praise', 'per': 10, 'room': 20, 'carry': 4},
      ]);
      expect(g.pointsToNext, 3);
      final h = g.nextHint!;
      expect(h.boost.key, 'praise');
      expect(h.times, 26); // 3점 × 10번 − 이미 쌓인 4번
      expect(h.actionIf, '칭찬 26번이면');
      expect(h.daysLeft, 0);
    });

    test('칭찬 양분이 가득 찼으면 다른 활동을 알려준다', () {
      final g = _g(score: 67, days: 10, boost: [
        {'key': 'praise', 'per': 10, 'room': 1, 'carry': 0},
        {'key': 'vote', 'per': 10, 'room': 10, 'carry': 2},
      ]);
      final h = g.nextHint!;
      expect(h.boost.key, 'vote');
      expect(h.actionIf, '수업맛집 28표면');
    });

    test('양분을 채워도 날이 모자라면 남은 날을 함께 알려준다', () {
      // Lv.7 → Lv.8: 170점 + 60일. 165점, 40일째
      final g = _g(score: 165, days: 40, boost: [
        {'key': 'praise', 'per': 10, 'room': 20, 'carry': 0},
      ]);
      final h = g.nextHint!;
      expect(h.times, 50);
      expect(h.daysLeft, 20);
    });

    test('날 조건에 걸렸으면 횟수 안내는 하지 않는다', () {
      final g = _g(score: 175, days: 40, boost: [
        {'key': 'praise', 'per': 10, 'room': 20, 'carry': 0},
      ]);
      expect(g.isDayLocked, isTrue);
      expect(g.nextHint, isNull);
    });
  });
}
