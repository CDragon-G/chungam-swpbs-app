/// 수업맛집 투표 모델.
class VoteSubject {
  VoteSubject({required this.id, required this.name, required this.orderIndex});
  final String id;
  final String name;
  final int orderIndex;

  factory VoteSubject.fromMap(Map<String, dynamic> m) => VoteSubject(
        id: m['id'] as String,
        name: m['name'] as String,
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
      );
}

class VoteRound {
  VoteRound({
    required this.id,
    required this.title,
    required this.votesPerWeek,
    required this.totalWeeks,
    required this.status,
    required this.createdAt,
    this.closedAt,
    this.startDate,
    this.endDate,
    this.voteWeekdays = const [],
  });
  final String id;
  final String title;
  final int votesPerWeek;
  final int totalWeeks;
  final String status; // open | closed
  final DateTime createdAt;
  final DateTime? closedAt;

  /// 학기 시작 때 미리 정해두는 투표 기간. null 이면 제한 없음.
  final DateTime? startDate;
  final DateTime? endDate;

  /// 투표 가능한 요일 (1=월 … 7=일). 비어 있으면 모든 수업일에 투표 가능.
  final List<int> voteWeekdays;

  bool get isOpen => status == 'open';

  static const _dayNames = ['월', '화', '수', '목', '금', '토', '일'];

  /// '금요일만' · '월·수·금' 처럼 사람이 읽는 문구. 지정이 없으면 null.
  String? get weekdayLabel {
    if (voteWeekdays.isEmpty) return null;
    final sorted = [...voteWeekdays]..sort();
    if (sorted.length == 1) return '${_dayNames[sorted.first - 1]}요일만';
    return sorted.map((d) => _dayNames[d - 1]).join('·');
  }

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  factory VoteRound.fromMap(Map<String, dynamic> m) => VoteRound(
        id: m['id'] as String,
        title: m['title'] as String,
        votesPerWeek: (m['votes_per_week'] as num).toInt(),
        totalWeeks: (m['total_weeks'] as num?)?.toInt() ?? 5,
        status: m['status'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        closedAt: _date(m['closed_at']),
        startDate: _date(m['start_date']),
        endDate: _date(m['end_date']),
        voteWeekdays: ((m['vote_weekdays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}

/// 진행 중 라운드의 재미 힌트 (교사·학생 공용, 학급명 비공개).
class VoteHint {
  VoteHint({
    required this.hasRound,
    this.title = '',
    this.votesPerWeek = 2,
    this.weekNow = 1,
    this.totalWeeks = 5,
    this.grades = const [],
  });
  final bool hasRound;
  final String title;
  final int votesPerWeek;
  final int weekNow;
  final int totalWeeks;
  final List<GradeHint> grades;

  factory VoteHint.fromMap(Map<String, dynamic> m) {
    if (m['has_round'] != true) return VoteHint(hasRound: false);
    return VoteHint(
      hasRound: true,
      title: m['title'] as String? ?? '',
      votesPerWeek: (m['votes_per_week'] as num?)?.toInt() ?? 2,
      weekNow: (m['week_now'] as num?)?.toInt() ?? 1,
      totalWeeks: (m['total_weeks'] as num?)?.toInt() ?? 5,
      grades: ((m['grades'] as List?) ?? const [])
          .map((g) => GradeHint.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList(),
    );
  }
}

class GradeHint {
  GradeHint({
    required this.grade,
    required this.top,
    required this.second,
    this.weekNow = 1,
    this.totalWeeks = 5,
    this.closed = false,
    this.pausedLabel,
  });
  final int grade;
  final int top;
  final int second;

  /// 학년별 주차 — 시험 기간처럼 쉬는 주는 여기 포함되지 않는다.
  final int weekNow;
  final int totalWeeks;

  /// 이 학년만 먼저 마감됐는가.
  final bool closed;

  /// 지금 이 학년이 쉬는 중이면 사유('중간고사' 등), 아니면 null.
  final String? pausedLabel;

  bool get isPaused => pausedLabel != null;

  int get gap => top - second;

  /// 재미 멘트 — 순위·학급은 비밀, 접전 상황만 살짝.
  String get message {
    if (closed) return '이 학년은 투표가 끝났어요. 결과를 확인해보세요! 🏆';
    if (isPaused) return '$pausedLabel 기간이라 이번 주는 쉬어가요. 시험 끝나고 다시 만나요!';
    if (top == 0) return '아직 첫 표를 기다리는 중이에요!';
    if (gap == 0) return '공동 1위! 다음 투표가 운명을 가른다! 🔥';
    if (gap == 1) return '앗! 1등과 2등이 단 1표 차이예요! 대역전 가능! ⚡';
    if (gap <= 3) return '1·2등이 $gap표 차이 초접전 중! 👀';
    return '현재 1등이 $gap표 차로 앞서는 중! 추격전을 기대해요 🏃';
  }

  factory GradeHint.fromMap(Map<String, dynamic> m) => GradeHint(
        grade: (m['grade'] as num).toInt(),
        top: (m['top'] as num?)?.toInt() ?? 0,
        second: (m['second'] as num?)?.toInt() ?? 0,
        weekNow: (m['week_now'] as num?)?.toInt() ?? 1,
        totalWeeks: (m['total_weeks'] as num?)?.toInt() ?? 5,
        closed: (m['closed'] as bool?) ?? false,
        pausedLabel: m['paused_label'] as String?,
      );
}

/// 투표를 쉬는 기간 — 3학년 중간고사처럼 학년마다 다른 시험 일정.
/// grade 가 null 이면 전 학년.
class VoteBlackout {
  VoteBlackout({
    required this.id,
    required this.grade,
    required this.startDate,
    required this.endDate,
    required this.label,
  });
  final String id;
  final int? grade;
  final DateTime startDate;
  final DateTime endDate;
  final String label;

  String get gradeLabel => grade == null ? '전 학년' : '$grade학년';

  bool containsToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(startDate) && !today.isAfter(endDate);
  }

  factory VoteBlackout.fromMap(Map<String, dynamic> m) => VoteBlackout(
        id: m['id'] as String,
        grade: (m['grade'] as num?)?.toInt(),
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: DateTime.parse(m['end_date'] as String),
        label: (m['label'] as String?) ?? '시험 기간',
      );
}

/// 라운드 전체 진행 상황 — 오늘 투표할 수 있는지 + 학년별 현황.
class VoteProgress {
  const VoteProgress({
    required this.todayOk,
    required this.grades,
    this.todayReason,
  });

  /// 오늘 이 라운드에 투표할 수 있는가 (지정한 시작·종료일·요일 기준).
  final bool todayOk;

  /// 투표할 수 없다면 그 이유 ('수업맛집 투표는 금요일에만 할 수 있어요.').
  final String? todayReason;
  final List<VoteGradeProgress> grades;

  static const empty = VoteProgress(todayOk: true, grades: []);

  factory VoteProgress.fromMap(Map<String, dynamic> m) => VoteProgress(
        todayOk: (m['today_ok'] as bool?) ?? true,
        todayReason: m['today_reason'] as String?,
        grades: ((m['grades'] as List?) ?? const [])
            .map((e) =>
                VoteGradeProgress.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// 라운드 안에서 한 학년이 어디까지 왔는지.
class VoteGradeProgress {
  VoteGradeProgress({
    required this.grade,
    required this.weekNow,
    required this.totalWeeks,
    required this.customWeeks,
    required this.closed,
    required this.votes,
    this.pausedLabel,
    this.closedAt,
  });
  final int grade;
  final int weekNow;
  final int totalWeeks;

  /// 라운드 기본 주차 대신 이 학년만 따로 정했는가.
  final bool customWeeks;
  final bool closed;
  final int votes;
  final String? pausedLabel;
  final DateTime? closedAt;

  bool get isPaused => pausedLabel != null;

  /// 투표를 받을 수 있는 상태인가.
  bool get isVotable => !closed && !isPaused;

  /// 정해진 주차를 다 채웠는가 — 관리자에게 마감을 권할 시점.
  bool get isFinished => !closed && weekNow >= totalWeeks;

  String get statusText {
    if (closed) return '마감';
    if (isPaused) return pausedLabel!;
    if (isFinished) return '$weekNow/$totalWeeks주차 · 마감 가능';
    return '$weekNow/$totalWeeks주차';
  }

  factory VoteGradeProgress.fromMap(Map<String, dynamic> m) {
    final closedAt = m['closed_at'] as String?;
    return VoteGradeProgress(
      grade: (m['grade'] as num).toInt(),
      weekNow: (m['week_now'] as num?)?.toInt() ?? 1,
      totalWeeks: (m['total_weeks'] as num?)?.toInt() ?? 5,
      customWeeks: (m['custom_weeks'] as bool?) ?? false,
      closed: (m['closed'] as bool?) ?? false,
      votes: (m['votes'] as num?)?.toInt() ?? 0,
      pausedLabel: m['paused_label'] as String?,
      closedAt: closedAt == null ? null : DateTime.parse(closedAt),
    );
  }
}

class ClassVote {
  ClassVote({
    required this.id,
    required this.subject,
    required this.grade,
    required this.classNum,
    required this.weekKey,
    required this.createdAt,
  });
  final String id;
  final String subject;
  final int grade;
  final int classNum;
  final String weekKey;
  final DateTime createdAt;

  String get classLabel => '$grade학년 $classNum반';

  factory ClassVote.fromMap(Map<String, dynamic> m) => ClassVote(
        id: m['id'] as String,
        subject: m['subject'] as String,
        grade: (m['grade'] as num).toInt(),
        classNum: (m['class_num'] as num).toInt(),
        weekKey: m['week_key'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class VoteTallyRow {
  VoteTallyRow({required this.grade, required this.classNum, required this.votes});
  final int grade;
  final int classNum;
  final int votes;

  String get classLabel => '$grade학년 $classNum반';

  factory VoteTallyRow.fromMap(Map<String, dynamic> m) => VoteTallyRow(
        grade: (m['grade'] as num).toInt(),
        classNum: (m['class_num'] as num).toInt(),
        votes: (m['votes'] as num).toInt(),
      );
}
