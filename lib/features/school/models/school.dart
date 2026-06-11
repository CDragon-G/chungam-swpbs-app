class School {
  School({
    required this.id,
    required this.name,
    required this.region,
    required this.level,
    required this.schoolCode,
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String region;
  final String level;
  final String schoolCode;
  final String? createdBy;
  final DateTime createdAt;

  factory School.fromMap(Map<String, dynamic> map) => School(
        id: map['id'] as String,
        name: map['name'] as String,
        region: map['region'] as String,
        level: map['level'] as String,
        schoolCode: map['school_code'] as String,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
