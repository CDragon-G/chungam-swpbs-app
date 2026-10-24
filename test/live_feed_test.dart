import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/features/feed/live_feed.dart';

void main() {
  final now = DateTime(2026, 11, 18, 8, 30);

  LiveFeed feed() => LiveFeed.fromMap({
        'ok': true,
        'today': {
          'students': 800,
          'checkins': 200,
          'exchanges': 12,
          'praise': 31,
          'mail': 0,
        },
        'exchanges': [
          {
            'label': '2-3 신*용',
            'item': '따뜻한 어묵',
            'emoji': '🍢',
            'at': now
                .subtract(const Duration(seconds: 40))
                .toUtc()
                .toIso8601String(),
          },
          {
            'label': '1-1 김*싹',
            'item': '점심시간 신청곡 (한 곡)',
            'emoji': '🎵',
            'at': now
                .subtract(const Duration(hours: 3))
                .toUtc()
                .toIso8601String(),
          },
        ],
        'events': [
          {
            'kind': 'honor_top',
            'label': '3-2 김*수',
            'detail': '3학년 2반',
            'at': now
                .subtract(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
          },
        ],
        'honor_tops': ['1-1 이*원', '1-2 박*진'],
        'hof': {
          'school': '2-1 이*원',
          'grades': [
            {'grade': 1, 'label': '1-4 최*아'},
          ],
        },
        'gardener': null,
      });

  test('교환 소식: 누가 · 언제 · 무엇을', () {
    final notes = CloudNotes.build(
        feed: feed(), events: const [], now: now, teacher: false);
    final ex = notes.where((n) => n.key.startsWith('ex:')).toList();
    expect(ex.first.top, '방금 · 2-3 신*용님이');
    expect(ex.first.main, "🍢 '따뜻한 어묵' 교환!");
    expect(ex.first.fresh, isTrue);
    // 긴 강화물 이름은 줄여서 구름이 화면보다 넓어지지 않게
    expect(ex[1].main.contains('…'), isTrue);
    expect(ex[1].top, '3시간 전 · 1-1 김*싹님이');
    expect(ex[1].fresh, isFalse);
  });

  test('오늘 숫자와 명예 소식', () {
    final notes = CloudNotes.build(
        feed: feed(), events: const [], now: now, teacher: true);
    final mains = notes.map((n) => n.main).toList();
    expect(mains, contains('🛍️ 벌써 12번 교환했어요'));
    expect(mains, contains('✅ 200명 참여 · 25%'));
    expect(mains, contains('💚 31번 오갔어요'));
    expect(mains, contains('👑 3-2 김*수, 반 1위로!'));
    expect(mains, contains('🏆 전교 1위 2-1 이*원'));
    // 0인 숫자는 말하지 않는다
    expect(mains.any((m) => m.contains('편지')), isFalse);
  });

  test('구름 글씨는 한 줄 18자 안팎', () {
    final notes = CloudNotes.build(
        feed: feed(), events: const [], now: now, teacher: true);
    for (final n in notes) {
      expect(n.top.runes.length, lessThanOrEqualTo(22), reason: n.top);
      expect(n.main.runes.length, lessThanOrEqualTo(22), reason: n.main);
    }
  });

  test('서버가 아직 073 전이면 구름 없이', () {
    final notes = CloudNotes.build(
        feed: null, events: const [], now: now, teacher: false);
    expect(notes, isEmpty);
  });
}
