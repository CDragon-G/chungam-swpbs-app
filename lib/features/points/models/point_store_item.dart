class PointStoreItem {
  PointStoreItem({
    required this.id,
    required this.schoolId,
    required this.name,
    this.description,
    required this.costPoints,
    this.stock,
    required this.isActive,
    required this.orderIndex,
    this.emoji = '🎁',
    this.grade,
    this.classNum,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String schoolId;
  final String name;
  final String? description;
  final int costPoints;
  final int? stock; // null = unlimited
  final bool isActive;
  final int orderIndex;
  final String emoji;
  final int? grade; // null = 전교 공통
  final int? classNum; // null = 전교 공통
  final String? createdBy; // 등록 교사 user_id
  final String? createdByName; // 등록 교사 이름 (표시용)
  final DateTime createdAt;

  bool get isUnlimited => stock == null;
  bool get isSoldOut => stock != null && stock! <= 0;

  /// 특정 학급 전용 상품인가 (담임 학급 상점).
  bool get isClassItem => grade != null && classNum != null;

  String get scopeLabel => isClassItem ? '$grade학년 $classNum반' : '전교 공통';

  factory PointStoreItem.fromMap(Map<String, dynamic> map) => PointStoreItem(
        id: map['id'] as String,
        schoolId: map['school_id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        costPoints: (map['cost_points'] as num).toInt(),
        stock: (map['stock'] as num?)?.toInt(),
        isActive: (map['is_active'] as bool?) ?? true,
        orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
        emoji: (map['emoji'] as String?)?.trim().isNotEmpty == true
            ? (map['emoji'] as String).trim()
            : '🎁',
        grade: (map['grade'] as num?)?.toInt(),
        classNum: (map['class_num'] as num?)?.toInt(),
        createdBy: map['created_by'] as String?,
        createdByName: (map['created_by_name'] as String?)?.trim().isNotEmpty == true
            ? (map['created_by_name'] as String).trim()
            : null,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
