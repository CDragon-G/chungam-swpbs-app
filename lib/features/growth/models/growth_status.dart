/// 학교 공동 새싹 성장 상태 (school_growth RPC 결과).
class GrowthStatus {
  GrowthStatus({
    required this.schoolName,
    required this.score,
    required this.days,
    required this.missions,
    required this.activity,
  });

  final String schoolName;
  final int score; // 0 ~ 240
  final int days; // 도입 후 경과일
  final List<GrowthMission> missions;
  final GrowthActivity activity;

  // ── 레벨 (12단계) ───────────────────────────────
  // 점수 만점은 240 (성장 미션 80 + 활동 양분 160).
  // Lv.7 열매나무까지는 한 해 안에 닿을 수 있게 두었다. 실제로 충암중이
  // 한 학기 만에 도착했다. 거기서 끝내면 더 키울 것이 없어지므로
  // Lv.8부터는 '점수'와 '함께한 날'을 같이 본다. 나무는 몰라도
  // 숲은 한 학기에 만들어지지 않는다.
  static const levelThresholds = [
    0, 15, 40, 70, 100, 130, 160, 175, 190, 205, 220, 235,
  ];

  /// 레벨별로 필요한 '도입 후 경과일'. Lv.7까지는 시간 조건이 없다.
  static const levelDays = [
    0, 0, 0, 0, 0, 0, 0, 120, 240, 400, 550, 730,
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

  /// 다음 레벨까지 진행률 0.0~1.0 (최고 레벨이면 1.0)
  double get progressToNext {
    if (isMaxLevel) return 1.0;
    if (isGateLocked) return 1.0; // 점수는 찼고 열쇠만 남음
    if (isDayLocked) {
      // 점수는 찼고 시간만 남았다 — 남은 날로 진행률을 보여준다.
      final curD = levelDays[level - 1];
      final nextD = levelDays[level];
      if (nextD <= curD) return 1.0;
      return ((days - curD) / (nextD - curD)).clamp(0.0, 1.0);
    }
    final cur = levelThresholds[level - 1];
    final next = levelThresholds[level];
    return ((score - cur) / (next - cur)).clamp(0.0, 1.0);
  }

  int get pointsToNext =>
      isMaxLevel ? 0 : (levelThresholds[level] - score).clamp(0, 999);

  factory GrowthStatus.fromMap(Map<String, dynamic> m) => GrowthStatus(
        schoolName: m['school_name'] as String? ?? '우리 학교',
        score: (m['score'] as num?)?.toInt() ?? 0,
        days: (m['days'] as num?)?.toInt() ?? 0,
        missions: ((m['missions'] as List?) ?? const [])
            .map((e) =>
                GrowthMission.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        activity: GrowthActivity.fromMap(
            Map<String, dynamic>.from((m['activity'] as Map?) ?? {})),
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
  });

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
      );
}
