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
    this.yearCount,
    this.totalCount,
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

  /// 이번 학년도 누적 · 전체 누적 (072 이전 서버면 null)
  final int? yearCount;
  final int? totalCount;

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
        yearCount: (m['year_count'] as num?)?.toInt(),
        totalCount: (m['total_count'] as num?)?.toInt(),
      );
}

/// 현황을 볼 기간.
enum KodrPeriodMode { month, year, all }

/// 현황 화면에서 고른 기간. [month] 는 그 달의 1일 (월별일 때만 쓴다).
class KodrPeriod {
  const KodrPeriod(this.mode, this.month);

  factory KodrPeriod.thisMonth() {
    final now = DateTime.now();
    return KodrPeriod(KodrPeriodMode.month, DateTime(now.year, now.month));
  }

  final KodrPeriodMode mode;
  final DateTime month;

  String get yearMonth =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  bool get isThisMonth {
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  KodrPeriod withMode(KodrPeriodMode m) => KodrPeriod(m, month);
  KodrPeriod withMonth(DateTime m) =>
      KodrPeriod(KodrPeriodMode.month, DateTime(m.year, m.month));

  @override
  bool operator ==(Object other) =>
      other is KodrPeriod && other.mode == mode && other.month == month;

  @override
  int get hashCode => Object.hash(mode, month);
}

/// 달별 건수 (이번 학년도).
class KodrMonthCount {
  const KodrMonthCount({
    required this.month,
    required this.recordCount,
    required this.studentCount,
  });

  final DateTime month;
  final int recordCount;
  final int studentCount;

  factory KodrMonthCount.fromMap(Map<String, dynamic> m) {
    final p = (m['year_month'] as String).split('-');
    return KodrMonthCount(
      month: DateTime(int.parse(p[0]), int.parse(p[1])),
      recordCount: (m['record_count'] as num?)?.toInt() ?? 0,
      studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 기간별 현황.
class KodrPeriodSummary {
  const KodrPeriodSummary({
    required this.items,
    required this.months,
    required this.total,
  });

  final List<KodrSummaryEntry> items;

  /// 이번 학년도의 달별 건수 (072 이전 서버면 비어 있다)
  final List<KodrMonthCount> months;
  final int total;
}

/// 한 학생의 누적 이력.
class KodrHistory {
  const KodrHistory({
    required this.name,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.joined,
    required this.isCurrent,
    required this.total,
    required this.yearCount,
    required this.windowCount,
    required this.windowDays,
    required this.topBehaviors,
    required this.topPlaces,
    required this.records,
  });

  final String name;
  final int? grade;
  final int? classNum;
  final int? studentNum;
  final bool joined;

  /// 지금 다니는 학생인가 (졸업 · 전출이면 false)
  final bool isCurrent;
  final int total;
  final int yearCount;
  final int windowCount;
  final int windowDays;
  final List<(String, int)> topBehaviors;
  final List<(String, int)> topPlaces;
  final List<KodrHistoryRecord> records;

  String get label => (grade != null && classNum != null && studentNum != null)
      ? '$name ($grade-$classNum-$studentNum)'
      : name;

  static List<(String, int)> _tops(dynamic v) => ((v as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .map((e) => ('${e['label']}', (e['count'] as num?)?.toInt() ?? 0))
      .toList();

  factory KodrHistory.fromMap(Map<String, dynamic> m) {
    final st = Map<String, dynamic>.from((m['student'] as Map?) ?? const {});
    final c = Map<String, dynamic>.from((m['counts'] as Map?) ?? const {});
    return KodrHistory(
      name: (st['name'] as String?) ?? '',
      grade: (st['grade'] as num?)?.toInt(),
      classNum: (st['class_num'] as num?)?.toInt(),
      studentNum: (st['student_num'] as num?)?.toInt(),
      joined: st['joined'] == true,
      isCurrent: st['is_current'] != false,
      total: (c['total'] as num?)?.toInt() ?? 0,
      yearCount: (c['year'] as num?)?.toInt() ?? 0,
      windowCount: (c['window'] as num?)?.toInt() ?? 0,
      windowDays: (c['window_days'] as num?)?.toInt() ?? 30,
      topBehaviors: _tops(m['top_behaviors']),
      topPlaces: _tops(m['top_places']),
      records: ((m['records'] as List?) ?? const [])
          .map((e) =>
              KodrHistoryRecord.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// 누적 이력의 기록 한 건.
class KodrHistoryRecord {
  const KodrHistoryRecord({
    required this.id,
    required this.occurredDate,
    required this.schoolYear,
    required this.behavior,
    this.place,
    this.situation,
    this.immediateResponse,
    this.secondaryResponse,
    this.studentReaction,
    this.authorRole,
    this.note,
    this.studentGrade,
    this.studentClass,
    this.teacherName,
  });

  final String id;
  final DateTime occurredDate;

  /// 학년도 (3월에 시작) — 2026 이면 2026.3 ~ 2027.2
  final int schoolYear;
  final String behavior;
  final String? place;
  final String? situation;
  final String? immediateResponse;
  final String? secondaryResponse;
  final String? studentReaction;
  final String? authorRole;
  final String? note;

  /// 기록 당시의 학년 · 반
  final int? studentGrade;
  final int? studentClass;
  final String? teacherName;

  static String? _text(dynamic v) {
    final s = (v as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory KodrHistoryRecord.fromMap(Map<String, dynamic> m) {
    final d = DateTime.parse(m['occurred_date'] as String);
    return KodrHistoryRecord(
      id: m['id'] as String,
      occurredDate: d,
      schoolYear: (m['school_year'] as num?)?.toInt() ??
          (d.month < 3 ? d.year - 1 : d.year),
      behavior: (m['behavior'] as String?) ?? '',
      place: _text(m['place']),
      situation: _text(m['situation']),
      immediateResponse: _text(m['immediate_response']),
      secondaryResponse: _text(m['secondary_response']),
      studentReaction: _text(m['student_reaction']),
      authorRole: _text(m['author_role']),
      note: _text(m['note']),
      studentGrade: (m['student_grade'] as num?)?.toInt(),
      studentClass: (m['student_class'] as num?)?.toInt(),
      teacherName: _text(m['teacher_name']),
    );
  }
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
