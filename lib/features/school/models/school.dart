class School {
  School({
    required this.id,
    required this.name,
    required this.region,
    required this.level,
    required this.schoolCode,
    this.teacherCode,
    this.createdBy,
    required this.createdAt,
    this.subscriptionStatus = 'active',
    this.subscriptionExpiresAt,
  });

  final String id;
  final String name;
  final String region;
  final String level;
  final String schoolCode;
  final String? teacherCode;
  final String? createdBy;
  final DateTime createdAt;
  final String subscriptionStatus; // 'pending' | 'active' | 'expired'
  final DateTime? subscriptionExpiresAt;

  bool get isActive => subscriptionStatus == 'active';

  /// 학교 급명을 뗀 약칭. '충암중학교'→'충암', '대광고등학교'→'대광'.
  /// '○○인' 같은 배지 이름에 끼워넣는 데 쓴다.
  String get shortName =>
      name.replaceFirst(RegExp(r'(초등학교|중학교|고등학교|초|중|고)$'), '').trim();

  factory School.fromMap(Map<String, dynamic> map) => School(
        id: map['id'] as String,
        name: map['name'] as String,
        region: map['region'] as String,
        level: map['level'] as String,
        schoolCode: map['school_code'] as String,
        teacherCode: map['teacher_code'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        subscriptionStatus:
            (map['subscription_status'] as String?) ?? 'active',
        subscriptionExpiresAt: map['subscription_expires_at'] == null
            ? null
            : DateTime.parse(map['subscription_expires_at'] as String),
      );
}
