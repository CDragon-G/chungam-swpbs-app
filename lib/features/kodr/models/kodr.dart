/// K-ODR 월별 집계 한 줄 (학생별).
class KodrSummaryEntry {
  KodrSummaryEntry({
    required this.studentId,
    required this.nickname,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.recordCount,
    required this.needsCico,
  });

  final String studentId;
  final String nickname;
  final int grade;
  final int classNum;
  final int studentNum;
  final int recordCount;
  final bool needsCico;

  String get classLabel => '$grade-$classNum-$studentNum';

  factory KodrSummaryEntry.fromMap(Map<String, dynamic> m) => KodrSummaryEntry(
        studentId: m['student_id'] as String,
        nickname: m['nickname'] as String,
        grade: m['grade'] as int,
        classNum: m['class_num'] as int,
        studentNum: m['student_num'] as int,
        recordCount: (m['record_count'] as num).toInt(),
        needsCico: (m['needs_cico'] as bool?) ?? false,
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
