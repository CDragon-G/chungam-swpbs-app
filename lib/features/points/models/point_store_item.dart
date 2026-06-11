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
  final DateTime createdAt;

  bool get isUnlimited => stock == null;
  bool get isSoldOut => stock != null && stock! <= 0;

  factory PointStoreItem.fromMap(Map<String, dynamic> map) => PointStoreItem(
        id: map['id'] as String,
        schoolId: map['school_id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        costPoints: (map['cost_points'] as num).toInt(),
        stock: (map['stock'] as num?)?.toInt(),
        isActive: (map['is_active'] as bool?) ?? true,
        orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
