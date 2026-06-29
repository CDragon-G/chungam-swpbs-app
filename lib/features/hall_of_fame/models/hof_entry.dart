/// 명예의 전당 한 항목 (이달의 학생).
class HofEntry {
  HofEntry({
    required this.scope,
    required this.scopeLabel,
    required this.nickname,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.praiseCount,
    required this.checkinDays,
    required this.avgScore,
    required this.totalScore,
  });

  final String scope; // 'school' | 'grade' | 'class'
  final String scopeLabel; // '전교' | '1학년' | '1학년 1반'
  final String nickname;
  final int grade;
  final int classNum;
  final int studentNum;
  final int praiseCount;
  final int checkinDays;
  final double avgScore;
  final double totalScore;

  factory HofEntry.fromMap(Map<String, dynamic> m) => HofEntry(
        scope: m['scope'] as String,
        scopeLabel: m['scope_label'] as String,
        nickname: m['nickname'] as String,
        grade: m['grade'] as int,
        classNum: m['class_num'] as int,
        studentNum: m['student_num'] as int,
        praiseCount: (m['praise_count'] as num?)?.toInt() ?? 0,
        checkinDays: (m['checkin_days'] as num?)?.toInt() ?? 0,
        avgScore: (m['avg_score'] as num?)?.toDouble() ?? 0,
        totalScore: (m['total_score'] as num?)?.toDouble() ?? 0,
      );

  /// 이름 마스킹: 신창용 → 신*용, 김민 → 김*
  String get maskedName {
    final n = nickname.trim();
    if (n.length <= 1) return n;
    if (n.length == 2) return '${n[0]}*';
    return '${n[0]}${'*' * (n.length - 2)}${n[n.length - 1]}';
  }

  /// 학년·반·번호 표기 (1-1-10)
  String get classLabel => '$grade-$classNum-$studentNum';
}
