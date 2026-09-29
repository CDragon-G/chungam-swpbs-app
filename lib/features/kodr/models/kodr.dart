/// K-ODR 을 기록할 수 있는 학생 — 명렬표 한 줄 (가입 여부와 상관없이).
class KodrStudentOption {
  const KodrStudentOption({
    required this.rosterId,
    required this.name,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.joined,
  });

  final String rosterId;
  final String name;
  final int grade;
  final int classNum;
  final int studentNum;

  /// 앱에 가입했는가. 가입 전이어도 K-ODR 은 기록할 수 있다.
  final bool joined;

  String get classLabel => '$grade-$classNum-$studentNum';

  factory KodrStudentOption.fromMap(Map<String, dynamic> m) =>
      KodrStudentOption(
        rosterId: m['roster_id'] as String,
        name: (m['name'] as String?) ?? '',
        grade: (m['grade'] as num?)?.toInt() ?? 0,
        classNum: (m['class_num'] as num?)?.toInt() ?? 0,
        studentNum: (m['student_num'] as num?)?.toInt() ?? 0,
        joined: m['joined'] == true,
      );
}

/// K-ODR 월별 집계 한 줄 (학생별).
class KodrSummaryEntry {
  KodrSummaryEntry({
    required this.subjectId,
    required this.studentId,
    required this.nickname,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.recordCount,
    required this.needsCico,
    required this.joined,
  });

  /// '그 학생' — 명렬표 줄 (명렬표에 없으면 계정)
  final String subjectId;

  /// 앱 계정. 가입하지 않은 학생이면 null — CICO 는 가입 뒤에 시작할 수 있다.
  final String? studentId;
  final String nickname;
  final int grade;
  final int classNum;
  final int studentNum;
  final int recordCount;
  final bool needsCico;
  final bool joined;

  String get classLabel => '$grade-$classNum-$studentNum';

  factory KodrSummaryEntry.fromMap(Map<String, dynamic> m) => KodrSummaryEntry(
        subjectId: m['subject_id'] as String,
        studentId: m['student_id'] as String?,
        nickname: (m['name'] as String?) ?? '',
        grade: (m['grade'] as num?)?.toInt() ?? 0,
        classNum: (m['class_num'] as num?)?.toInt() ?? 0,
        studentNum: (m['student_num'] as num?)?.toInt() ?? 0,
        recordCount: (m['record_count'] as num?)?.toInt() ?? 0,
        needsCico: (m['needs_cico'] as bool?) ?? false,
        joined: m['joined'] == true,
      );
}

/// K-ODR 기록 한 건 (조회용).
class KodrRecord {
  KodrRecord({
    required this.id,
    required this.occurredDate,
    required this.behavior,
    this.place,
    this.situation,
    this.note,
    required this.createdAt,
  });

  final String id;
  final DateTime occurredDate;
  final String behavior;
  final String? place;
  final String? situation;
  final String? note;
  final DateTime createdAt;

  factory KodrRecord.fromMap(Map<String, dynamic> m) => KodrRecord(
        id: m['id'] as String,
        occurredDate: DateTime.parse(m['occurred_date'] as String),
        behavior: m['behavior'] as String,
        place: m['place'] as String?,
        situation: m['situation'] as String?,
        note: m['note'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
