class DailyCheckin {
  DailyCheckin({
    required this.id,
    required this.userId,
    required this.schoolId,
    required this.checkinDate,
    required this.answers,
    required this.totalScore,
    required this.totalPossible,
    required this.scorePct,
    required this.categoryScores,
    this.comment,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String schoolId;
  final DateTime checkinDate;
  final Map<String, bool> answers; // rule_id -> kept?
  final int totalScore;
  final int totalPossible;
  final double scorePct;
  final Map<String, double> categoryScores;
  final String? comment;
  final DateTime createdAt;

  factory DailyCheckin.fromMap(Map<String, dynamic> map) {
    final rawAnswers = (map['answers'] as Map?)?.cast<String, dynamic>() ?? {};
    final answers = <String, bool>{
      for (final e in rawAnswers.entries) e.key: e.value == true,
    };
    final rawCats = (map['category_scores'] as Map?)?.cast<String, dynamic>() ?? {};
    final cats = <String, double>{
      for (final e in rawCats.entries) e.key: (e.value as num).toDouble(),
    };
    return DailyCheckin(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      schoolId: map['school_id'] as String,
      checkinDate: DateTime.parse(map['checkin_date'] as String),
      answers: answers,
      totalScore: (map['total_score'] as num?)?.toInt() ?? 0,
      totalPossible: (map['total_possible'] as num?)?.toInt() ?? 0,
      scorePct: (map['score_pct'] as num?)?.toDouble() ?? 0,
      categoryScores: cats,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
