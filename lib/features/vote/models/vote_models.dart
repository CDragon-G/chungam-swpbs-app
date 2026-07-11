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
  });
  final String id;
  final String title;
  final int votesPerWeek;
  final int totalWeeks;
  final String status; // open | closed
  final DateTime createdAt;
  final DateTime? closedAt;

  bool get isOpen => status == 'open';

  factory VoteRound.fromMap(Map<String, dynamic> m) => VoteRound(
        id: m['id'] as String,
        title: m['title'] as String,
        votesPerWeek: (m['votes_per_week'] as num).toInt(),
        totalWeeks: (m['total_weeks'] as num?)?.toInt() ?? 5,
        status: m['status'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        closedAt: m['closed_at'] == null
            ? null
            : DateTime.parse(m['closed_at'] as String),
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
  GradeHint({required this.grade, required this.top, required this.second});
  final int grade;
  final int top;
  final int second;

  int get gap => top - second;

  /// 재미 멘트 — 순위·학급은 비밀, 접전 상황만 살짝.
  String get message {
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
      );
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
