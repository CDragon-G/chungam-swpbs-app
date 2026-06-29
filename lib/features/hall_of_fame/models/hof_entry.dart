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
        nickname: (m['nickname'] as String?) ?? '',
        grade: _toInt(m['grade']),
        classNum: _toInt(m['class_num']),
        studentNum: _toInt(m['student_num']),
        praiseCount: _toInt(m['praise_count']),
        checkinDays: _toInt(m['checkin_days']),
        avgScore: _toDouble(m['avg_score']),
        totalScore: _toDouble(m['total_score']),
      );

  // Supabase는 numeric을 문자열로, int를 숫자로 직렬화할 수 있어
  // 어느 쪽이 와도 안전하게 변환한다.
  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

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
