class BadgeDef {
  BadgeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.iconEmoji,
    required this.conditionType,
    required this.conditionValue,
  });

  final String id;
  final String name;
  final String description;
  final String iconEmoji;
  final String conditionType;
  final int conditionValue;

  /// '○○인' 토큰을 학교 약칭으로 치환한 표시용 이름.
  /// 예) '○○인' + 충암중학교 → '충암인'. 학교명이 없으면 '우리학교인'.
  String displayName(String? schoolShortName) => name.contains('○○')
      ? name.replaceAll('○○', schoolShortName?.isNotEmpty == true
          ? schoolShortName!
          : '우리학교')
      : name;

  factory BadgeDef.fromMap(Map<String, dynamic> map) => BadgeDef(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String,
        iconEmoji: map['icon_emoji'] as String,
        conditionType: map['condition_type'] as String,
        conditionValue: (map['condition_value'] as int?) ?? 0,
      );
}

class UserBadge {
  UserBadge({
    required this.id,
    required this.userId,
    required this.badgeId,
    required this.earnedAt,
  });

  final String id;
  final String userId;
  final String badgeId;
  final DateTime earnedAt;

  factory UserBadge.fromMap(Map<String, dynamic> map) => UserBadge(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        badgeId: map['badge_id'] as String,
        earnedAt: DateTime.parse(map['earned_at'] as String),
      );
}
