/// 🎁 교사 라운지 모델 — 강화물·원데이클래스·포인트 내역.
library;

class TeacherRewardItem {
  TeacherRewardItem({
    required this.id,
    required this.name,
    this.description,
    required this.costPoints,
    this.stock,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? description;
  final int costPoints;
  final int? stock; // null = 무제한
  final bool isActive;

  bool get soldOut => stock != null && stock! <= 0;

  factory TeacherRewardItem.fromMap(Map<String, dynamic> m) =>
      TeacherRewardItem(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        costPoints: (m['cost_points'] as num).toInt(),
        stock: (m['stock'] as num?)?.toInt(),
        isActive: m['is_active'] as bool? ?? true,
      );
}

class TeacherExchange {
  TeacherExchange({
    required this.id,
    required this.teacherId,
    required this.itemName,
    required this.costPoints,
    required this.status,
    required this.requestedAt,
    this.teacherName,
  });

  final String id;
  final String teacherId;
  final String itemName;
  final int costPoints;
  final String status; // pending | fulfilled | cancelled
  final DateTime requestedAt;
  final String? teacherName;

  String get statusLabel => switch (status) {
        'pending' => '대기 중',
        'fulfilled' => '지급 완료',
        _ => '취소됨',
      };

  factory TeacherExchange.fromMap(Map<String, dynamic> m) => TeacherExchange(
        id: m['id'] as String,
        teacherId: m['teacher_id'] as String,
        itemName: m['item_name'] as String,
        costPoints: (m['cost_points'] as num).toInt(),
        status: m['status'] as String,
        requestedAt: DateTime.parse(m['requested_at'] as String).toLocal(),
      );

  TeacherExchange withName(String? name) => TeacherExchange(
        id: id,
        teacherId: teacherId,
        itemName: itemName,
        costPoints: costPoints,
        status: status,
        requestedAt: requestedAt,
        teacherName: name,
      );
}

class TeacherClassInfo {
  TeacherClassInfo({
    required this.id,
    required this.hostId,
    required this.title,
    this.description,
    required this.costPoints,
    required this.minParticipants,
    this.maxParticipants,
    this.durationMinutes,
    this.scheduledAt,
    this.location,
    required this.status,
    this.hostName,
    this.enrolledCount = 0,
    this.enrolledNames = const [],
    this.myEnrolled = false,
  });

  final String id;
  final String hostId;
  final String title;
  final String? description;
  final int costPoints;
  final int minParticipants;
  final int? maxParticipants;
  final int? durationMinutes;
  final DateTime? scheduledAt;
  final String? location;
  final String status; // recruiting | confirmed | done | cancelled
  final String? hostName;
  final int enrolledCount;
  final List<String> enrolledNames;
  final bool myEnrolled;

  String get statusLabel => switch (status) {
        'recruiting' => '모집 중',
        'confirmed' => '개설 확정',
        'done' => '진행 완료',
        _ => '취소됨',
      };

  factory TeacherClassInfo.fromMap(Map<String, dynamic> m) => TeacherClassInfo(
        id: m['id'] as String,
        hostId: m['host_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        costPoints: (m['cost_points'] as num).toInt(),
        minParticipants: (m['min_participants'] as num).toInt(),
        maxParticipants: (m['max_participants'] as num?)?.toInt(),
        durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
        scheduledAt: m['scheduled_at'] == null
            ? null
            : DateTime.parse(m['scheduled_at'] as String).toLocal(),
        location: m['location'] as String?,
        status: m['status'] as String,
      );

  TeacherClassInfo copyWith({
    String? hostName,
    int? enrolledCount,
    List<String>? enrolledNames,
    bool? myEnrolled,
  }) =>
      TeacherClassInfo(
        id: id,
        hostId: hostId,
        title: title,
        description: description,
        costPoints: costPoints,
        minParticipants: minParticipants,
        maxParticipants: maxParticipants,
        durationMinutes: durationMinutes,
        scheduledAt: scheduledAt,
        location: location,
        status: status,
        hostName: hostName ?? this.hostName,
        enrolledCount: enrolledCount ?? this.enrolledCount,
        enrolledNames: enrolledNames ?? this.enrolledNames,
        myEnrolled: myEnrolled ?? this.myEnrolled,
      );
}

class TeacherPointTx {
  TeacherPointTx({
    required this.points,
    required this.source,
    required this.createdAt,
  });

  final int points;
  final String source;
  final DateTime createdAt;

  String get sourceLabel => switch (source) {
        'praise' => '칭찬 보내기',
        'kodr' => 'K-ODR 작성',
        'cico' => 'CICO 점검',
        'vote' => '수업맛집 투표',
        'announcement' => '공지 작성',
        'quiz' => '초성 퀴즈 정답',
        'class_host' => '클래스 개설 확정',
        'class_enroll' => '클래스 신청',
        'exchange' => '강화물 교환',
        'refund' => '환불',
        _ => '기타',
      };

  factory TeacherPointTx.fromMap(Map<String, dynamic> m) => TeacherPointTx(
        points: (m['points'] as num).toInt(),
        source: m['source'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
