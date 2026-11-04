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
    this.limitPerStudent,
    this.limitPeriod = 'total',
    this.playerSlots,
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

  /// 학생 1명이 [limitPeriod] 동안 교환할 수 있는 횟수 (null = 제한 없음, 075)
  final int? limitPerStudent;

  /// 'total' 전체 · 'day' 하루 · 'week' 이번 주 · 'month' 이번 달
  final String limitPeriod;

  bool get hasLimit => limitPerStudent != null;

  /// 스포츠 경기의 선수 인원 (함께 키우기에서만, null = 스포츠 경기 아님, 077)
  final int? playerSlots;

  /// 보탤 때 선수 / 응원을 고르는 함께 키우기
  bool get isSports => isGroup && playerSlots != null;

  /// '하루 1번' · '1인 2번'
  String get limitLabel {
    final n = limitPerStudent;
    if (n == null) return '';
    return switch (limitPeriod) {
      'day' => '하루 $n번',
      'week' => '한 주 $n번',
      'month' => '한 달 $n번',
      _ => '1인 $n번',
    };
  }

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
        createdByName:
            (map['created_by_name'] as String?)?.trim().isNotEmpty == true
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
        limitPerStudent: (map['limit_per_student'] as num?)?.toInt(),
        limitPeriod: (map['limit_period'] as String?) ?? 'total',
        playerSlots: (map['player_slots'] as num?)?.toInt(),
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
    this.playerSlots,
    this.players = 0,
    this.supporters = 0,
    this.supporterRaised = 0,
    this.supporterCap = 0,
    this.myRole,
  });

  final int goal;
  final int raised;
  final int people; // 보탠 사람 수
  final int myAmount; // 내가 보탠 합계
  final bool achieved;
  final bool closed;
  final int? maxPerStudent;
  final List<GroupContributor> top; // 기여 TOP 3

  // ── 스포츠 경기 (077) ──
  final int? playerSlots; // 선수 인원 (null = 스포츠 경기 아님)
  final int players; // 선수로 참여한 학생 수
  final int supporters; // 응원한 학생 수
  final int supporterRaised; // 응원 몫 합계
  final int supporterCap; // 응원 몫 상한 (목표의 30%)
  final String? myRole; // 'player' · 'supporter' · null (아직 안 보탬)

  bool get isSports => playerSlots != null;
  bool get isPlayer => myRole == 'player';
  bool get isSupporter => myRole == 'supporter';
  int get playerRaised => raised - supporterRaised;
  bool get playersFull => playerSlots != null && players >= playerSlots!;
  int get supporterLeft =>
      supporterRaised >= supporterCap ? 0 : supporterCap - supporterRaised;

  /// 선수로 새로 들어오거나 응원에서 선수로 바꿀 수 있는가
  bool get canJoinAsPlayer => isSports && !isPlayer && !playersFull;

  /// 막대에서 선수 몫 · 응원 몫이 차지하는 비율 (0~1)
  double get playerProgress =>
      goal <= 0 ? 0 : (playerRaised / goal).clamp(0.0, 1.0);
  double get supporterProgress =>
      goal <= 0 ? 0 : (supporterRaised / goal).clamp(0.0, 1.0 - playerProgress);

  int get remain => (goal - raised) < 0 ? 0 : goal - raised;
  double get progress => goal <= 0 ? 0 : (raised / goal).clamp(0.0, 1.0);
  int get percent => (progress * 100).round();

  /// 내가 지금 더 보탤 수 있는 최대 포인트 (한도와 남은 금액 중 작은 쪽).
  /// 스포츠 경기에서 응원으로 보탤 때는 남은 응원 몫도 넘지 않는다.
  int myMaxAddable(int balance, {String? role}) {
    var cap = remain;
    if (maxPerStudent != null) {
      final left = maxPerStudent! - myAmount;
      if (left < cap) cap = left;
    }
    if (isSports && !isPlayer && (role ?? myRole) == 'supporter') {
      if (supporterLeft < cap) cap = supporterLeft;
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
            .map((e) =>
                GroupContributor.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        playerSlots: (m['player_slots'] as num?)?.toInt(),
        players: (m['players'] as num?)?.toInt() ?? 0,
        supporters: (m['supporters'] as num?)?.toInt() ?? 0,
        supporterRaised: (m['supporter_raised'] as num?)?.toInt() ?? 0,
        supporterCap: (m['supporter_cap'] as num?)?.toInt() ?? 0,
        myRole: m['my_role'] as String?,
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
