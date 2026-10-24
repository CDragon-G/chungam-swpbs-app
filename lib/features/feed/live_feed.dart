import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../notice/school_event.dart';

/// ☁️ 구름 소식 — 우리 학교에서 지금 일어나는 일 (school_live_feed, 073).
///
/// 서버가 학교마다 60초 동안 결과를 보관하므로 홈을 연 학생이 많아도 부담이 적다.
/// 이름은 서버에서 가려져 온다 ('2-3 신*용').
class LiveFeed {
  const LiveFeed({
    required this.students,
    required this.checkins,
    required this.exchangesToday,
    required this.praiseToday,
    required this.mailToday,
    required this.exchanges,
    required this.events,
    required this.honorTops,
    this.hofSchool,
    this.hofGrades = const [],
    this.gardener,
    this.gardenerAt,
  });

  final int students;
  final int checkins;
  final int exchangesToday;
  final int praiseToday;
  final int mailToday;
  final List<FeedExchange> exchanges; // 24시간, 최신 순
  final List<FeedEvent> events; // 48시간, 최신 순
  final List<String> honorTops; // 이 주의 명예 식집사 (반별 1위)
  final String? hofSchool; // 이달의 명예의 전당 전교 1위
  final List<({int grade, String label})> hofGrades;
  final String? gardener; // 2주 꾸준 식집사 (선정 후 3일)
  final DateTime? gardenerAt;

  static DateTime? _t(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory LiveFeed.fromMap(Map<String, dynamic> m) {
    final today = Map<String, dynamic>.from((m['today'] as Map?) ?? {});
    final hof =
        m['hof'] is Map ? Map<String, dynamic>.from(m['hof'] as Map) : null;
    final g = m['gardener'] is Map
        ? Map<String, dynamic>.from(m['gardener'] as Map)
        : null;
    return LiveFeed(
      students: _i(today['students']),
      checkins: _i(today['checkins']),
      exchangesToday: _i(today['exchanges']),
      praiseToday: _i(today['praise']),
      mailToday: _i(today['mail']),
      exchanges: ((m['exchanges'] as List?) ?? const [])
          .map((e) => FeedExchange.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      events: ((m['events'] as List?) ?? const [])
          .map((e) => FeedEvent.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      honorTops:
          ((m['honor_tops'] as List?) ?? const []).map((e) => '$e').toList(),
      hofSchool: hof?['school'] as String?,
      hofGrades: ((hof?['grades'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => (grade: _i(e['grade']), label: '${e['label'] ?? ''}'))
          .where((e) => e.label.isNotEmpty)
          .toList(),
      gardener: g?['label'] as String?,
      gardenerAt: _t(g?['at']),
    );
  }
}

class FeedExchange {
  const FeedExchange(
      {required this.label, required this.item, required this.emoji, this.at});
  final String label; // '2-3 신*용'
  final String item; // '점심시간 신청곡'
  final String emoji;
  final DateTime? at;

  factory FeedExchange.fromMap(Map<String, dynamic> m) => FeedExchange(
        label: '${m['label'] ?? ''}',
        item: '${m['item'] ?? ''}',
        emoji: (m['emoji'] as String?)?.trim().isNotEmpty == true
            ? (m['emoji'] as String).trim()
            : '🎁',
        at: LiveFeed._t(m['at']),
      );
}

class FeedEvent {
  const FeedEvent(
      {required this.kind, required this.label, this.detail, this.at});
  final String kind; // honor_top | hof_top
  final String label;
  final String? detail;
  final DateTime? at;

  factory FeedEvent.fromMap(Map<String, dynamic> m) => FeedEvent(
        kind: '${m['kind'] ?? ''}',
        label: '${m['label'] ?? ''}',
        detail: m['detail'] as String?,
        at: LiveFeed._t(m['at']),
      );
}

final liveFeedProvider = FutureProvider.autoDispose<LiveFeed?>((ref) async {
  try {
    final res = await SupabaseService.client.rpc('school_live_feed');
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) return null;
    return LiveFeed.fromMap(m);
  } catch (_) {
    // 073 을 아직 실행하지 않은 서버 — 구름 없이 홈을 보여준다
    return null;
  }
});

/// 구름 한 개에 실을 소식.
/// [top] 작은 윗줄(언제 · 누가), [main] 큰 아랫줄(무엇을). 둘 다 한 줄로만 쓴다.
class CloudNote {
  const CloudNote({
    required this.key,
    required this.top,
    required this.main,
    this.tone = CloudTone.plain,
    this.fresh = false,
  });

  /// 같은 소식을 알아보는 열쇠 (새 소식인지 판단)
  final String key;
  final String top;
  final String main;
  final CloudTone tone;

  /// 방금 일어난 일 — 줄 맨 앞으로 끼워 넣는다
  final bool fresh;
}

enum CloudTone { plain, exchange, honor, fame, promo }

/// 구름 소식 문장 만들기. 한 줄은 18자 안팎 (구름이 화면보다 넓어지지 않게).
class CloudNotes {
  CloudNotes._();

  static String _ago(DateTime? at, DateTime now) {
    if (at == null) return '오늘';
    final d = now.difference(at);
    if (d.inMinutes < 2) return '방금';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    return '어제';
  }

  static String _short(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : '${t.substring(0, max - 1)}…';
  }

  static bool _fresh(DateTime? at, DateTime now) =>
      at != null && now.difference(at).inMinutes < 30;

  static List<CloudNote> build({
    required LiveFeed? feed,
    required List<SchoolEvent> events,
    required DateTime now,
    required bool teacher,
  }) {
    final out = <CloudNote>[];

    // 1) 이벤트 홍보
    for (final e in events.take(2)) {
      final d = e.dDay;
      out.add(CloudNote(
        key: 'promo:${e.id}',
        top: d == null || d == '진행 중' ? '지금 진행 중' : '곧 열려요 · $d',
        main: '${e.emoji} ${_short(e.plainTitle, 14)}',
        tone: CloudTone.promo,
      ));
    }

    final f = feed;
    if (f == null) return out;

    // 2) 1위가 바뀐 소식
    for (final ev in f.events) {
      final when = _ago(ev.at, now);
      switch (ev.kind) {
        case 'honor_top':
          out.add(CloudNote(
            key: 'ev:honor:${ev.label}:${ev.at?.millisecondsSinceEpoch}',
            top: '$when · 이 주의 명예 식집사',
            main: '👑 ${ev.label}, 반 1위로!',
            tone: CloudTone.honor,
            fresh: _fresh(ev.at, now),
          ));
        case 'hof_top':
          out.add(CloudNote(
            key: 'ev:hof:${ev.label}:${ev.at?.millisecondsSinceEpoch}',
            top: '$when · 이달의 명예의 전당',
            main: '🏆 ${ev.label}, 전교 1위!',
            tone: CloudTone.fame,
            fresh: _fresh(ev.at, now),
          ));
      }
    }

    // 3) 방금 교환한 강화물
    for (final x in f.exchanges.take(6)) {
      out.add(CloudNote(
        key: 'ex:${x.label}:${x.item}:${x.at?.millisecondsSinceEpoch}',
        top: '${_ago(x.at, now)} · ${x.label}님이',
        main: "${x.emoji} '${_short(x.item, 9)}' 교환!",
        tone: CloudTone.exchange,
        fresh: _fresh(x.at, now),
      ));
    }

    // 4) 오늘 숫자
    if (f.exchangesToday > 0) {
      out.add(CloudNote(
        key: 'today:exchanges',
        top: '오늘의 교환소',
        main: '🛍️ 벌써 ${f.exchangesToday}번 교환했어요',
        tone: CloudTone.exchange,
      ));
    }
    if (f.checkins > 0) {
      final pct = f.students > 0 ? (f.checkins * 100 / f.students).round() : 0;
      out.add(CloudNote(
        key: 'today:checkins',
        top: '오늘 자기점검',
        main: pct > 0 ? '✅ ${f.checkins}명 참여 · $pct%' : '✅ ${f.checkins}명 참여',
      ));
    }
    if (f.praiseToday > 0) {
      out.add(CloudNote(
        key: 'today:praise',
        top: '오늘 선생님 칭찬',
        main: '💚 ${f.praiseToday}번 오갔어요',
      ));
    }
    if (f.mailToday > 0) {
      out.add(CloudNote(
        key: 'today:mail',
        top: '오늘 칭찬 우체통',
        main: '💌 편지 ${f.mailToday}통이 오갔어요',
      ));
    }

    // 5) 명예 — 2주 꾸준 식집사 · 이달의 명예의 전당 · 이 주의 명예 식집사
    if (f.gardener != null) {
      out.add(CloudNote(
        key: 'gardener:${f.gardener}',
        top: '2주 꾸준 식집사',
        main: '🌿 ${f.gardener} 선정!',
        tone: CloudTone.honor,
        fresh: _fresh(f.gardenerAt, now),
      ));
    }
    if (f.hofSchool != null) {
      out.add(CloudNote(
        key: 'hof:school',
        top: '이달의 명예의 전당',
        main: '🏆 전교 1위 ${f.hofSchool}',
        tone: CloudTone.fame,
      ));
    }
    for (final g in f.hofGrades) {
      out.add(CloudNote(
        key: 'hof:${g.grade}',
        top: '이달의 ${g.grade}학년 대표',
        main: '🌿 ${g.label}',
        tone: CloudTone.fame,
      ));
    }
    // 반이 많으면 몇 명만 (돌아가며 다른 반이 나오도록 매번 섞는다)
    final tops = [...f.honorTops]..shuffle();
    for (final t in tops.take(teacher ? 4 : 3)) {
      out.add(CloudNote(
        key: 'honor:$t',
        top: '이 주의 명예 식집사',
        main: '👑 $t',
        tone: CloudTone.honor,
      ));
    }
    return out;
  }
}
