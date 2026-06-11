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
  final int amount; // positive=earn, negative=spend
  final String reason;
  final String? periodKey;
  final String? description;
  final DateTime createdAt;

  bool get isEarn => amount > 0;
  bool get isSpend => amount < 0;

  String get displayLabel {
    if (description != null && description!.isNotEmpty) return description!;
    switch (reason) {
      case 'checkin_daily':
        return '일일 자기점검 참여';
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

  factory PointTransaction.fromMap(Map<String, dynamic> map) => PointTransaction(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        schoolId: map['school_id'] as String,
        amount: (map['amount'] as num).toInt(),
        reason: map['reason'] as String,
        periodKey: map['period_key'] as String?,
        description: map['description'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
