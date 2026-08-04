class Praise {
  Praise({
    required this.id,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.studentId,
    this.studentName,
    this.teacherName,
  });

  final String id;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final String? studentId;
  final String? studentName; // join 시 채워짐 (교사 화면용)
  final String? teacherName; // 칭찬을 보낸 선생님 (학생 화면용)

  factory Praise.fromMap(Map<String, dynamic> m) => Praise(
        id: m['id'] as String,
        message: m['message'] as String,
        isRead: (m['is_read'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String),
        studentId: m['student_id'] as String?,
        teacherName: m['teacher_name'] as String?,
      );
}
