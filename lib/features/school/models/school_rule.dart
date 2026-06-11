class SchoolRule {
  SchoolRule({
    required this.id,
    required this.schoolId,
    required this.space,
    required this.category,
    required this.ruleText,
    required this.orderIndex,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String schoolId;
  final String space;
  final String category;
  final String ruleText;
  final int orderIndex;
  final bool isActive;
  final DateTime createdAt;

  factory SchoolRule.fromMap(Map<String, dynamic> map) => SchoolRule(
        id: map['id'] as String,
        schoolId: map['school_id'] as String,
        space: map['space'] as String,
        category: map['category'] as String,
        ruleText: map['rule_text'] as String,
        orderIndex: (map['order_index'] as int?) ?? 0,
        isActive: (map['is_active'] as bool?) ?? true,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  SchoolRule copyWith({
    String? space,
    String? category,
    String? ruleText,
    int? orderIndex,
    bool? isActive,
  }) =>
      SchoolRule(
        id: id,
        schoolId: schoolId,
        space: space ?? this.space,
        category: category ?? this.category,
        ruleText: ruleText ?? this.ruleText,
        orderIndex: orderIndex ?? this.orderIndex,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}
