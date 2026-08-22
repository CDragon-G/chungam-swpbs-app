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
    this.itemType = 'individual',
    this.maxPerStudent,
    this.achievedAt,
    this.closedAt,
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

  /// 'individual' = 한 명이 교환 · 'group' = 여러 명이 포인트를 보태는 함께 키우기
  final String itemType;

  /// 함께 키우기에서 한 사람이 보탤 수 있는 최대 포인트 (null = 무제한)
  final int? maxPerStudent;

  /// 목표를 채운 시각 (함께 키우기)
  final DateTime? achievedAt;

  /// 지급 완료 또는 취소된 시각
  final DateTime? closedAt;

  bool get isGroup => itemType == 'group';
  bool get isAchieved => achievedAt != null;
  bool get isClosed => closedAt != null;

  /// 함께 키우기에서 cost_points 는 목표 총액을 뜻한다.
  int get goalPoints => costPoints;

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
        itemType: (map['item_type'] as String?) ?? 'individual',
        maxPerStudent: (map['max_per_student'] as num?)?.toInt(),
        achievedAt: map['achieved_at'] == null
            ? null
            : DateTime.parse(map['achieved_at'] as String),
        closedAt: map['closed_at'] == null
            ? null
            : DateTime.parse(map['closed_at'] as String),
      );
}


/// 함께 키우기 현황 — group_item_status RPC 결과.
class GroupItemStatus {
  const GroupItemStatus({
    required this.goal,
    required this.raised,
    required this.people,
    required this.myAmount,
    required this.achieved,
    required this.closed,
    required this.top,
    this.maxPerStudent,
  });

  final int goal;
  final int raised;
  final int people;      // 보탠 사람 수
  final int myAmount;    // 내가 보탠 합계
  final bool achieved;
  final bool closed;
  final int? maxPerStudent;
  final List<GroupContributor> top; // 기여 TOP 3

  int get remain => (goal - raised) < 0 ? 0 : goal - raised;
  double get progress => goal <= 0 ? 0 : (raised / goal).clamp(0.0, 1.0);
  int get percent => (progress * 100).round();

  /// 내가 지금 더 보탤 수 있는 최대 포인트 (한도와 남은 금액 중 작은 쪽).
  int myMaxAddable(int balance) {
    var cap = remain;
    if (maxPerStudent != null) {
      final left = maxPerStudent! - myAmount;
      if (left < cap) cap = left;
    }
    if (balance < cap) cap = balance;
    return cap < 0 ? 0 : cap;
  }

  factory GroupItemStatus.fromMap(Map<String, dynamic> m) => GroupItemStatus(
        goal: (m['goal'] as num?)?.toInt() ?? 0,
        raised: (m['raised'] as num?)?.toInt() ?? 0,
        people: (m['people'] as num?)?.toInt() ?? 0,
        myAmount: (m['my_amount'] as num?)?.toInt() ?? 0,
        achieved: (m['achieved'] as bool?) ?? false,
        closed: (m['closed'] as bool?) ?? false,
        maxPerStudent: (m['max_per_student'] as num?)?.toInt(),
        top: ((m['top'] as List?) ?? const [])
            .map((e) => GroupContributor.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class GroupContributor {
  const GroupContributor({required this.nickname, required this.amount});
  final String nickname;
  final int amount;

  factory GroupContributor.fromMap(Map<String, dynamic> m) => GroupContributor(
        nickname: (m['nickname'] as String?) ?? '이름 없음',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
      );
}
