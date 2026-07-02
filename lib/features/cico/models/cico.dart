/// CICO (Check-In/Check-Out) 모델.
/// Supabase가 numeric을 문자열로 직렬화할 수 있어 숫자 파싱은 전부 안전 변환.

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

/// CICO 등록 (학생 1명당 진행 중 1건).
class CicoEnrollment {
  CicoEnrollment({
    required this.id,
    required this.schoolId,
    required this.studentId,
    this.mentorId,
    required this.goalPct,
    required this.startDate,
    this.endDate,
    required this.status,
    this.reason,
    this.studentName,
    this.studentLabel,
    this.mentorName,
  });

  final String id;
  final String schoolId;
  final String studentId;
  final String? mentorId;
  final int goalPct;
  final DateTime startDate;
  final DateTime? endDate;
  final String status; // active | graduated | stopped
  final String? reason;

  // 조회 후 클라이언트에서 채워지는 표시용 필드
  final String? studentName;
  final String? studentLabel; // 1-2-10
  final String? mentorName;

  bool get isActive => status == 'active';

  factory CicoEnrollment.fromMap(Map<String, dynamic> m) => CicoEnrollment(
        id: m['id'] as String,
        schoolId: m['school_id'] as String,
        studentId: m['student_id'] as String,
        mentorId: m['mentor_id'] as String?,
        goalPct: _toInt(m['goal_pct']),
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: m['end_date'] == null
            ? null
            : DateTime.parse(m['end_date'] as String),
        status: (m['status'] as String?) ?? 'active',
        reason: m['reason'] as String?,
      );

  CicoEnrollment withNames({
    String? studentName,
    String? studentLabel,
    String? mentorName,
  }) =>
      CicoEnrollment(
        id: id,
        schoolId: schoolId,
        studentId: studentId,
        mentorId: mentorId,
        goalPct: goalPct,
        startDate: startDate,
        endDate: endDate,
        status: status,
        reason: reason,
        studentName: studentName ?? this.studentName,
        studentLabel: studentLabel ?? this.studentLabel,
        mentorName: mentorName ?? this.mentorName,
      );
}

/// 하루치 CICO 카드.
class CicoDaily {
  CicoDaily({
    required this.id,
    required this.enrollmentId,
    required this.entryDate,
    this.checkinNote,
    this.checkoutNote,
    this.studentReflection,
    this.parentSignature,
    this.parentSignedAt,
    required this.totalScore,
    required this.possibleScore,
    required this.pct,
  });

  final String id;
  final String enrollmentId;
  final DateTime entryDate;
  final String? checkinNote;
  final String? checkoutNote;
  final String? studentReflection;
  final String? parentSignature; // base64 PNG
  final DateTime? parentSignedAt;
  final int totalScore;
  final int possibleScore;
  final double pct;

  bool get hasParentSign =>
      parentSignature != null && parentSignature!.isNotEmpty;

  factory CicoDaily.fromMap(Map<String, dynamic> m) => CicoDaily(
        id: m['id'] as String,
        enrollmentId: m['enrollment_id'] as String,
        entryDate: DateTime.parse(m['entry_date'] as String),
        checkinNote: m['checkin_note'] as String?,
        checkoutNote: m['checkout_note'] as String?,
        studentReflection: m['student_reflection'] as String?,
        parentSignature: m['parent_signature'] as String?,
        parentSignedAt: m['parent_signed_at'] == null
            ? null
            : DateTime.parse(m['parent_signed_at'] as String),
        totalScore: _toInt(m['total_score']),
        possibleScore: _toInt(m['possible_score']),
        pct: _toDouble(m['pct']),
      );
}

/// 항목별 0/1/2 점수.
class CicoScore {
  CicoScore({
    required this.id,
    required this.dailyId,
    this.ruleId,
    required this.itemLabel,
    this.category,
    this.space,
    required this.score,
  });

  final String id;
  final String dailyId;
  final String? ruleId;
  final String itemLabel;
  final String? category;
  final String? space;
  final int score; // 0 | 1 | 2

  factory CicoScore.fromMap(Map<String, dynamic> m) => CicoScore(
        id: m['id'] as String,
        dailyId: m['daily_id'] as String,
        ruleId: m['rule_id'] as String?,
        itemLabel: (m['item_label'] as String?) ?? '',
        category: m['category'] as String?,
        space: m['space'] as String?,
        score: _toInt(m['score']),
      );
}

/// 점수 입력용 (저장 전, rule 기반으로 생성).
class CicoScoreInput {
  CicoScoreInput({
    this.ruleId,
    required this.itemLabel,
    this.category,
    this.space,
    this.score = 0,
  });

  final String? ruleId;
  final String itemLabel;
  final String? category;
  final String? space;
  int score;

  Map<String, dynamic> toJson() => {
        'rule_id': ruleId ?? '',
        'item_label': itemLabel,
        'category': category,
        'space': space,
        'score': score,
      };
}
