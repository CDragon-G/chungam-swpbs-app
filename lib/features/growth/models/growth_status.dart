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
  final int score; // 0 ~ 200
  final int days; // 도입 후 경과일
  final List<GrowthMission> missions;
  final GrowthActivity activity;

  // ── 레벨 (7단계) ────────────────────────────────
  static const levelThresholds = [0, 15, 40, 70, 105, 145, 180];
  static const levelEmojis = ['🌰', '🌱', '🌿', '🪴', '🌳', '🌸', '🍎'];
  static const levelNames = ['씨앗', '새싹', '푸른 잎', '어린나무', '튼튼한 나무', '꽃나무', '열매나무'];

  /// 1~7
  int get level {
    var lv = 1;
    for (var i = 0; i < levelThresholds.length; i++) {
      if (score >= levelThresholds[i]) lv = i + 1;
    }
    return lv;
  }

  String get levelEmoji => levelEmojis[level - 1];
  String get levelName => levelNames[level - 1];
  bool get isMaxLevel => level >= levelThresholds.length;

  /// 다음 레벨까지 진행률 0.0~1.0 (최고 레벨이면 1.0)
  double get progressToNext {
    if (isMaxLevel) return 1.0;
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
      );
}
