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
    required this.status,
    required this.createdAt,
    this.closedAt,
  });
  final String id;
  final String title;
  final int votesPerWeek;
  final String status; // open | closed
  final DateTime createdAt;
  final DateTime? closedAt;

  bool get isOpen => status == 'open';

  factory VoteRound.fromMap(Map<String, dynamic> m) => VoteRound(
        id: m['id'] as String,
        title: m['title'] as String,
        votesPerWeek: (m['votes_per_week'] as num).toInt(),
        status: m['status'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        closedAt: m['closed_at'] == null
            ? null
            : DateTime.parse(m['closed_at'] as String),
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
