class SchoolLeaderboardEntry {
  SchoolLeaderboardEntry({
    required this.id,
    required this.name,
    required this.region,
    required this.level,
    required this.studentCount,
    required this.checkinCount30d,
    required this.participants30d,
    required this.avgScore30d,
    required this.schoolScore,
  });

  final String id;
  final String name;
  final String region;
  final String level;
  final int studentCount;
  final int checkinCount30d;
  final int participants30d;
  final double avgScore30d;
  final int schoolScore;

  factory SchoolLeaderboardEntry.fromMap(Map<String, dynamic> map) =>
      SchoolLeaderboardEntry(
        id: map['id'] as String,
        name: map['name'] as String,
        region: map['region'] as String,
        level: map['level'] as String,
        studentCount: (map['student_count'] as num?)?.toInt() ?? 0,
        checkinCount30d: (map['checkin_count_30d'] as num?)?.toInt() ?? 0,
        participants30d: (map['participants_30d'] as num?)?.toInt() ?? 0,
        avgScore30d: (map['avg_score_30d'] as num?)?.toDouble() ?? 0,
        schoolScore: (map['school_score'] as num?)?.toInt() ?? 0,
      );
}
