/// 학교 공동 새싹 성장 상태 (school_growth RPC 결과).
class GrowthStatus {
  GrowthStatus({
    required this.schoolName,
    required this.score,
    required this.days,
    required this.yearLabel,
    required this.history,
    required this.missions,
    required this.activity,
    this.boosts = const [],
  });

  final String schoolName;
  final int score; // 0 ~ 240 (이번 학년도 기준)
  final int days; // 이번 학년도 경과일 (학기 중 도입이면 도입일부터)
  final String yearLabel; // '2026학년도'
  final List<GrowthYear> history; // 지난 학년도 최고 기록
  final List<GrowthMission> missions;
  final GrowthActivity activity;

  /// 횟수로 셀 수 있는 양분 — 다음 레벨까지 '무엇을 몇 번' 하면 되는지 계산용 (073).
  final List<GrowthBoost> boosts;

  // ── 레벨 (12단계) ───────────────────────────────
  // 점수 만점은 240 (성장 미션 80 + 활동 양분 160).
  // 성장은 학년도(3/1~) 단위다. 3월이면 새 학생들과 다시 씨앗부터 키운다.
  // 그래서 12단계 전체가 한 학년도 안에 들어가야 한다 — Lv.12 모두의 숲은
  // 3월에 시작해 12월쯤 닿는 자리다.
  static const levelThresholds = [
    0, 15, 40, 70, 100, 130, 160, 170, 182, 194, 206, 218,
  ];

  /// 레벨별로 필요한 '이번 학년도 경과일'. Lv.7까지는 시간 조건이 없다.
  /// 3/1 기준으로 60일≈4월 말, 100일≈6월 중순, 150일≈7월 말,
  /// 210일≈9월 말, 270일≈11월 하순.
  static const levelDays = [
    0, 0, 0, 0, 0, 0, 0, 60, 100, 150, 210, 270,
  ];

  static const levelEmojis = [
    '🌰', '🌱', '🌿', '🪴', '🌳', '🌸', '🍎', '🧺', '🌲', '🏞️', '🌄', '🌏',
  ];
  static const levelNames = [
    '씨앗', '새싹', '푸른 잎', '어린나무', '튼튼한 나무', '꽃나무', '열매나무',
    '나눔나무', '이음나무', '작은 숲', '우리 숲', '모두의 숲',
  ];

  bool _done(String key) => missions.any((m) => m.key == key && m.done);

  /// 점수만으로 도달 가능한 레벨 (1~12)
  int get scoreLevel {
    var lv = 1;
    for (var i = 0; i < levelThresholds.length; i++) {
      if (score >= levelThresholds[i]) lv = i + 1;
    }
    return lv;
  }

  /// 관문이 허용하는 최대 레벨 — 핵심 미션을 안 하면 점수가 있어도 잠김.
  ///   Lv.2 규칙 / Lv.3 명단+첫점검 / Lv.4 절반가입+첫칭찬 /
  ///   Lv.5 첫 K-ODR / Lv.6 CICO 또는 수업맛집 / Lv.7~ 점수만
  int get gateCap {
    if (!_done('rules')) return 1;
    if (!(_done('roster') && _done('checkin'))) return 2;
    if (!(_done('join') && _done('praise'))) return 3;
    if (!_done('kodr')) return 4;
    if (!(_done('cico') || _done('vote'))) return 5;
    return levelThresholds.length;
  }

  /// 함께한 날이 허용하는 최대 레벨 (Lv.7까지는 항상 열려 있다).
  int get dayCap {
    var lv = 1;
    for (var i = 0; i < levelDays.length; i++) {
      if (days >= levelDays[i]) lv = i + 1;
    }
    return lv;
  }

  /// 실제 레벨 = 점수 · 관문 · 함께한 날 중 가장 낮은 쪽.
  int get level {
    var lv = scoreLevel;
    if (gateCap < lv) lv = gateCap;
    if (dayCap < lv) lv = dayCap;
    return lv;
  }

  /// 점수는 충분한데 핵심 미션이 없어 잠긴 상태인가.
  bool get isGateLocked =>
      !isMaxLevel && scoreLevel > level && gateCap == level;

  /// 점수는 충분한데 아직 함께한 날이 모자라 잠긴 상태인가.
  bool get isDayLocked =>
      !isMaxLevel && scoreLevel > level && !isGateLocked && dayCap == level;

  /// 다음 단계가 열리기까지 남은 날 (시간 조건이 없으면 0).
  int get daysToNext =>
      isMaxLevel ? 0 : (levelDays[level] - days).clamp(0, 99999);

  /// 잠금을 여는 열쇠 미션 안내 (관문에 걸렸을 때만).
  String? get gateKeyLabel {
    if (!isGateLocked) return null;
    switch (level) {
      case 1:
        return '우리 학교 규칙 만들기';
      case 2:
        return !_done('roster') ? '전교생 명단 등록하기' : '첫 일일 자기점검 받기';
      case 3:
        return !_done('join') ? '학생 절반 이상 가입하기' : '첫 칭찬 보내기';
      case 4:
        return '첫 K-ODR 기록하기';
      case 5:
        return 'CICO 또는 수업맛집 시작하기';
    }
    return null;
  }

  String get levelEmoji => levelEmojis[level - 1];
  String get levelName => levelNames[level - 1];
  bool get isMaxLevel => level >= levelThresholds.length;

  /// 레벨별 일러스트 에셋 (1~12).
  static String assetFor(int lv) =>
      'assets/growth/stage${lv.clamp(1, levelThresholds.length)}.png';
  String get levelAsset => assetFor(level);

  /// 다음 레벨까지 진행률 0.0~1.0 (최고 레벨이면 1.0).
  ///
  /// 같은 레벨 안에서는 줄어들지 않는다. 점수(서버가 내려가지 않게 보관, 073)와
  /// 함께한 날은 둘 다 늘기만 하므로, 그 둘로만 만든다.
  ///   · 날 조건이 없는 레벨: 양분 진행률
  ///   · 날 조건이 있는 레벨: 양분 진행률과 날 진행률의 평균
  ///     (예전에는 양분이 차는 순간 '날 진행률' 로 바뀌어 80% → 50% 처럼 뒷걸음질했다)
  double get progressToNext {
    if (isMaxLevel) return 1.0;
    if (isGateLocked) return 1.0; // 양분은 찼고 열쇠만 남음
    final cur = levelThresholds[level - 1];
    final next = levelThresholds[level];
    final scoreP = ((score - cur) / (next - cur)).clamp(0.0, 1.0);
    final curD = levelDays[level - 1];
    final nextD = levelDays[level];
    if (nextD <= curD) return scoreP;
    final dayP = ((days - curD) / (nextD - curD)).clamp(0.0, 1.0);
    return (scoreP + dayP) / 2;
  }

  int get pointsToNext =>
      isMaxLevel ? 0 : (levelThresholds[level] - score).clamp(0, 999);

  /// 다음 레벨까지 무엇을 몇 번 하면 되는지 (양분이 모자랄 때만).
  /// 칭찬을 먼저 권하고, 칭찬 양분이 가득 찼으면 다른 항목을 권한다.
  GrowthHint? get nextHint {
    if (isMaxLevel || isGateLocked || isDayLocked) return null;
    final need = pointsToNext;
    if (need <= 0) return null;
    for (final b in boosts) {
      if (b.room >= need) {
        return GrowthHint(
          boost: b,
          times: b.timesFor(need),
          points: need,
          // 양분을 채워도 함께한 날이 모자라면 그날까지 기다린다 (Lv.8~)
          daysLeft: daysToNext,
        );
      }
    }
    return null;
  }

  /// 새 학년도가 막 시작된 시기인가 (리셋을 설명해 줘야 하는 구간).
  bool get isNewYear => days <= 45;

  factory GrowthStatus.fromMap(Map<String, dynamic> m) => GrowthStatus(
        schoolName: m['school_name'] as String? ?? '우리 학교',
        score: (m['score'] as num?)?.toInt() ?? 0,
        days: (m['days'] as num?)?.toInt() ?? 0,
        yearLabel: m['year_label'] as String? ?? '',
        history: ((m['history'] as List?) ?? const [])
            .map((e) => GrowthYear.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        missions: ((m['missions'] as List?) ?? const [])
            .map((e) =>
                GrowthMission.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        activity: GrowthActivity.fromMap(
            Map<String, dynamic>.from((m['activity'] as Map?) ?? {})),
        boosts: ((m['boost'] as List?) ?? const [])
            .map(
                (e) => GrowthBoost.fromMap(Map<String, dynamic>.from(e as Map)))
            .where((b) => b.label.isNotEmpty)
            .toList(),
      );
}

/// 횟수로 셀 수 있는 양분 한 가지 (073 'boost').
/// 예: 칭찬 10번에 1점, 앞으로 7점까지 더 받을 수 있고, 지금 3번 쌓여 있음.
class GrowthBoost {
  const GrowthBoost({
    required this.key,
    required this.per,
    required this.room,
    required this.carry,
  });

  final String key; // praise | exchange | vote | weekly
  final int per; // 몇 번에 1점
  final int room; // 이 항목으로 더 받을 수 있는 점수
  final int carry; // 다음 1점을 향해 이미 쌓인 횟수

  /// [points] 점을 채우려면 몇 번 더 필요한가.
  int timesFor(int points) => (points * per - carry).clamp(1, 99999);

  /// 말풍선 · 진행바에 쓰는 이름과 단위
  String get label => switch (key) {
        'praise' => '칭찬',
        'exchange' => '교환',
        'vote' => '수업맛집',
        'weekly' => '주간 개근',
        _ => '',
      };
  String get emoji => switch (key) {
        'praise' => '💚',
        'exchange' => '🛍️',
        'vote' => '🍽️',
        'weekly' => '🔥',
        _ => '🌱',
      };
  String get unit => switch (key) {
        'vote' => '표',
        'weekly' => '회',
        'exchange' => '번',
        _ => '번',
      };

  factory GrowthBoost.fromMap(Map<String, dynamic> m) => GrowthBoost(
        key: m['key'] as String? ?? '',
        per: (m['per'] as num?)?.toInt() ?? 1,
        room: (m['room'] as num?)?.toInt() ?? 0,
        carry: (m['carry'] as num?)?.toInt() ?? 0,
      );
}

/// '칭찬 12번이면 Lv.8!' 같은 안내 한 줄의 재료.
class GrowthHint {
  const GrowthHint({
    required this.boost,
    required this.times,
    required this.points,
    this.daysLeft = 0,
  });
  final GrowthBoost boost;
  final int times;
  final int points;

  /// 양분을 채운 뒤에도 남는 날 (0 이면 양분만 채우면 바로 레벨업)
  final int daysLeft;

  /// '칭찬 12번'
  String get action => '${boost.label} $times${boost.unit}';

  /// '칭찬 12번이면' · '수업맛집 30표면' (받침에 따라 조사를 고른다)
  String get actionIf {
    final u = boost.unit.codeUnitAt(boost.unit.length - 1);
    final hasFinal = u >= 0xAC00 && u <= 0xD7A3 && (u - 0xAC00) % 28 != 0;
    return '$action${hasFinal ? '이면' : '면'}';
  }
}

/// 지난 학년도의 최고 기록. 리셋되어도 이건 남는다.
class GrowthYear {
  GrowthYear({required this.year, required this.level, required this.score});
  final String year; // '2026학년도'
  final int level;
  final int score;

  String get emoji =>
      GrowthStatus.levelEmojis[(level - 1).clamp(0, GrowthStatus.levelEmojis.length - 1)];
  String get name =>
      GrowthStatus.levelNames[(level - 1).clamp(0, GrowthStatus.levelNames.length - 1)];

  factory GrowthYear.fromMap(Map<String, dynamic> m) => GrowthYear(
        year: m['year'] as String? ?? '',
        level: (m['level'] as num?)?.toInt() ?? 1,
        score: (m['score'] as num?)?.toInt() ?? 0,
      );
}

class GrowthMission {
  GrowthMission({required this.key, required this.label, required this.done});
  final String key;
  final String label;
  final bool done;

  factory GrowthMission.fromMap(Map<String, dynamic> m) => GrowthMission(
        key: m['key'] as String? ?? '',
        label: m['label'] as String? ?? '',
        done: m['done'] == true,
      );
}

class GrowthActivity {
  GrowthActivity({
    required this.participation,
    required this.participationPts,
    required this.praiseTotal,
    required this.praisePts,
    required this.kodrMode,
    required this.kodrTotal,
    required this.kodrPts,
    required this.cicoGraduated,
    required this.cicoPts,
    required this.storeItems,
    required this.storePts,
    required this.exchanges,
    required this.exchangePts,
    required this.votesCast,
    required this.votePts,
    required this.announcements,
    required this.announcePts,
    required this.weeklyBonus,
    required this.weeklyPts,
    this.kept = const {},
  });

  /// 지금 값보다 이번 학년도 최고값이 높아서 그 값을 지키고 있는 항목 (073).
  /// 예: 'participation_pts' — 참여율이 잠깐 내려가도 양분은 그대로.
  final Set<String> kept;

  final double participation; // %
  final int participationPts;
  final int praiseTotal;
  final int praisePts;
  final String kodrMode; // early | down | up
  final int kodrTotal;
  final int kodrPts;
  final int cicoGraduated;
  final int cicoPts;
  final int storeItems; // 강화물 등록 수
  final int storePts;
  final int exchanges; // 교환 수령 처리 수
  final int exchangePts;
  final int votesCast; // 수업맛집 투표 참여 수
  final int votePts;
  final int announcements;
  final int announcePts;
  final int weeklyBonus; // 주간 개근 보너스 달성 수
  final int weeklyPts;

  String get kodrLabel => switch (kodrMode) {
        'early' => '기록 문화 만드는 중 (작성할수록 +)',
        'down' => 'K-ODR 감소 추세 — 예방이 작동 중! 🎉',
        _ => 'K-ODR 기록 유지 중',
      };

  factory GrowthActivity.fromMap(Map<String, dynamic> m) => GrowthActivity(
        participation: (m['participation'] as num?)?.toDouble() ?? 0,
        participationPts: (m['participation_pts'] as num?)?.toInt() ?? 0,
        praiseTotal: (m['praise_total'] as num?)?.toInt() ?? 0,
        praisePts: (m['praise_pts'] as num?)?.toInt() ?? 0,
        kodrMode: m['kodr_mode'] as String? ?? 'early',
        kodrTotal: (m['kodr_total'] as num?)?.toInt() ?? 0,
        kodrPts: (m['kodr_pts'] as num?)?.toInt() ?? 0,
        cicoGraduated: (m['cico_graduated'] as num?)?.toInt() ?? 0,
        cicoPts: (m['cico_pts'] as num?)?.toInt() ?? 0,
        storeItems: (m['store_items'] as num?)?.toInt() ?? 0,
        storePts: (m['store_pts'] as num?)?.toInt() ?? 0,
        exchanges: (m['exchanges'] as num?)?.toInt() ?? 0,
        exchangePts: (m['exchange_pts'] as num?)?.toInt() ?? 0,
        votesCast: (m['votes_cast'] as num?)?.toInt() ?? 0,
        votePts: (m['vote_pts'] as num?)?.toInt() ?? 0,
        announcements: (m['announcements'] as num?)?.toInt() ?? 0,
        announcePts: (m['announce_pts'] as num?)?.toInt() ?? 0,
        weeklyBonus: (m['weekly_bonus'] as num?)?.toInt() ?? 0,
        weeklyPts: (m['weekly_pts'] as num?)?.toInt() ?? 0,
        kept: ((m['kept'] as List?) ?? const []).map((e) => '$e').toSet(),
      );
}
