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
    this.fulfilledBy,
    this.note,
    this.studentNickname,
    this.studentGrade,
    this.studentClassNum,
    this.studentNum,
  });

  final String id;
  final String userId;
  final String schoolId;
  final String? itemId;
  final String itemName;
  final int costPoints;
  final String status; // pending | fulfilled | cancelled
  final DateTime requestedAt;
  final DateTime? fulfilledAt;
  final String? fulfilledBy;
  final String? note;

  // Optional fields when joined with profiles (for teacher view)
  final String? studentNickname;
  final int? studentGrade;
  final int? studentClassNum;
  final int? studentNum;

  bool get isPending => status == 'pending';
  bool get isFulfilled => status == 'fulfilled';
  bool get isCancelled => status == 'cancelled';

  String get statusLabel => switch (status) {
        'pending' => '대기 중',
        'fulfilled' => '수령 완료',
        'cancelled' => '취소됨',
        _ => status,
      };

  String? get classLabel {
    if (studentGrade == null) return null;
    return '${studentGrade}학년 ${studentClassNum ?? '-'}반 ${studentNum ?? '-'}번';
  }

  factory PointExchange.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return PointExchange(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      schoolId: map['school_id'] as String,
      itemId: map['item_id'] as String?,
      itemName: map['item_name'] as String,
      costPoints: (map['cost_points'] as num).toInt(),
      status: map['status'] as String,
      requestedAt: DateTime.parse(map['requested_at'] as String),
      fulfilledAt: map['fulfilled_at'] == null
          ? null
          : DateTime.parse(map['fulfilled_at'] as String),
      fulfilledBy: map['fulfilled_by'] as String?,
      note: map['note'] as String?,
      studentNickname: profile is Map ? profile['nickname'] as String? : null,
      studentGrade: profile is Map ? (profile['grade'] as num?)?.toInt() : null,
      studentClassNum:
          profile is Map ? (profile['class_num'] as num?)?.toInt() : null,
      studentNum:
          profile is Map ? (profile['student_num'] as num?)?.toInt() : null,
    );
  }
}
