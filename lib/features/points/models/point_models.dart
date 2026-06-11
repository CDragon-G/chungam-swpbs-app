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

  bool get unlimited => stock == null;
  bool get inStock => stock == null || stock! > 0;

  factory PointStoreItem.fromMap(Map<String, dynamic> m) => PointStoreItem(
        id: m['id'] as String,
        schoolId: m['school_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        costPoints: (m['cost_points'] as num).toInt(),
        stock: (m['stock'] as num?)?.toInt(),
        isActive: (m['is_active'] as bool?) ?? true,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class PointTransaction {
  PointTransaction({
    required this.id,
    required this.userId,
    required this.schoolId,
    required this.amount,
    required this.reason,
    this.periodKey,
    this.description,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String schoolId;
  final int amount;
  final String reason; // checkin_daily / checkin_weekly / exchange / refund
  final String? periodKey;
  final String? description;
  final DateTime createdAt;

  bool get isEarned => amount > 0;

  String get reasonLabel {
    switch (reason) {
      case 'checkin_daily':
        return '일일 점검 적립';
      case 'checkin_weekly':
        return '월~금 개근 보너스';
      case 'exchange':
        return '상품 교환';
      case 'refund':
        return '교환 취소 환불';
      default:
        return reason;
    }
  }

  factory PointTransaction.fromMap(Map<String, dynamic> m) => PointTransaction(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        schoolId: m['school_id'] as String,
        amount: (m['amount'] as num).toInt(),
        reason: m['reason'] as String,
        periodKey: m['period_key'] as String?,
        description: m['description'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class PointExchange {
  PointExchange({
    required this.id,
    required this.userId,
    required this.schoolId,
    this.itemId,
    required this.itemName,
    required this.costPoints,
    required this.status,
    required this.requestedAt,
    this.fulfilledAt,
    this.note,
    this.studentNickname,
    this.studentGrade,
    this.studentClass,
    this.studentNum,
  });

  final String id;
  final String userId;
  final String schoolId;
  final String? itemId;
  final String itemName;
  final int costPoints;
  final String status; // pending / fulfilled / cancelled
  final DateTime requestedAt;
  final DateTime? fulfilledAt;
  final String? note;

  // optional joined fields (teacher view)
  final String? studentNickname;
  final int? studentGrade;
  final int? studentClass;
  final int? studentNum;

  bool get isPending => status == 'pending';
  bool get isFulfilled => status == 'fulfilled';
  bool get isCancelled => status == 'cancelled';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '대기 중';
      case 'fulfilled':
        return '수령 완료';
      case 'cancelled':
        return '취소됨';
      default:
        return status;
    }
  }

  factory PointExchange.fromMap(Map<String, dynamic> m) {
    final p = m['profiles'] as Map<String, dynamic>?;
    return PointExchange(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      schoolId: m['school_id'] as String,
      itemId: m['item_id'] as String?,
      itemName: m['item_name'] as String,
      costPoints: (m['cost_points'] as num).toInt(),
      status: m['status'] as String,
      requestedAt: DateTime.parse(m['requested_at'] as String),
      fulfilledAt: m['fulfilled_at'] != null
          ? DateTime.parse(m['fulfilled_at'] as String)
          : null,
      note: m['note'] as String?,
      studentNickname: p?['nickname'] as String?,
      studentGrade: p?['grade'] as int?,
      studentClass: p?['class_num'] as int?,
      studentNum: p?['student_num'] as int?,
    );
  }
}

class SchoolLeaderboardEntry {
  SchoolLeaderboardEntry({
    required this.id,
    required this.name,
    required this.region,
    required this.level,
    required this.studentCount,
    required this.checkinCount30d,
    required this.participants30d,
    required this.avgScore30d,
    required this.schoolScore,
  });

  final String id;
  final String name;
  final String region;
  final String level;
  final int studentCount;
  final int checkinCount30d;
  final int participants30d;
  final double avgScore30d;
  final int schoolScore;

  factory SchoolLeaderboardEntry.fromMap(Map<String, dynamic> m) =>
      SchoolLeaderboardEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        region: m['region'] as String,
        level: m['level'] as String,
        studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
        checkinCount30d: (m['checkin_count_30d'] as num?)?.toInt() ?? 0,
        participants30d: (m['participants_30d'] as num?)?.toInt() ?? 0,
        avgScore30d: (m['avg_score_30d'] as num?)?.toDouble() ?? 0,
        schoolScore: (m['school_score'] as num?)?.toInt() ?? 0,
      );
}
