class Profile {
  Profile({
    required this.id,
    required this.userId,
    required this.role,
    required this.nickname,
    this.schoolId,
    this.grade,
    this.classNum,
    this.studentNum,
    this.teacherRole,
    this.notifyHour = 17,
    this.notifyMinute = 0,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String role; // 'teacher' | 'student'
  final String nickname;
  final String? schoolId;
  final int? grade;
  final int? classNum;
  final int? studentNum;
  final String? teacherRole; // 'admin' | 'regular' (teachers only)
  final int notifyHour;
  final int notifyMinute;
  final DateTime createdAt;

  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
  bool get isAdminTeacher => isTeacher && teacherRole == 'admin';
  bool get isRegularTeacher => isTeacher && teacherRole == 'regular';

  String get classLabel {
    if (grade == null || classNum == null) return '';
    return '$grade학년 $classNum반${studentNum != null ? ' $studentNum번' : ''}';
  }

  String get teacherRoleLabel {
    if (!isTeacher) return '';
    return teacherRole == 'admin' ? '관리자' : '일반 교사';
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        role: map['role'] as String,
        nickname: map['nickname'] as String,
        schoolId: map['school_id'] as String?,
        grade: map['grade'] as int?,
        classNum: map['class_num'] as int?,
        studentNum: map['student_num'] as int?,
        teacherRole: map['teacher_role'] as String?,
        notifyHour: (map['notify_hour'] as int?) ?? 17,
        notifyMinute: (map['notify_minute'] as int?) ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toInsert() => {
        'user_id': userId,
        'role': role,
        'nickname': nickname,
        if (schoolId != null) 'school_id': schoolId,
        if (grade != null) 'grade': grade,
        if (classNum != null) 'class_num': classNum,
        if (studentNum != null) 'student_num': studentNum,
        if (teacherRole != null) 'teacher_role': teacherRole,
        'notify_hour': notifyHour,
        'notify_minute': notifyMinute,
      };
}
