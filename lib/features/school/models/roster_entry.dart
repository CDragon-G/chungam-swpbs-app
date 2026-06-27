/// 학생 명단 한 줄 (교사가 업로드한 전교생 명단).
class RosterEntry {
  RosterEntry({
    required this.id,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.name,
    required this.pin,
    required this.claimed,
  });

  final String id;
  final int grade;
  final int classNum;
  final int studentNum;
  final String name;
  final String pin;
  final bool claimed;

  factory RosterEntry.fromMap(Map<String, dynamic> m) => RosterEntry(
        id: m['id'] as String,
        grade: m['grade'] as int,
        classNum: m['class_num'] as int,
        studentNum: m['student_num'] as int,
        name: m['name'] as String,
        pin: m['pin'] as String,
        claimed: (m['claimed'] as bool?) ?? false,
      );

  String get classLabel => '$grade학년 $classNum반 $studentNum번';
}

/// 붙여넣기/CSV 텍스트를 파싱한 결과 (업로드 전 미리보기용).
class RosterDraftRow {
  RosterDraftRow({
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.name,
  });

  final int grade;
  final int classNum;
  final int studentNum;
  final String name;

  Map<String, dynamic> toJson() => {
        'grade': grade,
        'class_num': classNum,
        'student_num': studentNum,
        'name': name,
      };
}

/// 엑셀에서 복사한 텍스트(탭/콤마 구분, 한 줄=한 학생)를 파싱한다.
/// 형식: 학년[탭]반[탭]번호[탭]이름  (헤더 줄은 자동 무시)
class RosterParser {
  RosterParser._();

  static (List<RosterDraftRow> rows, List<String> errors) parse(String raw) {
    final rows = <RosterDraftRow>[];
    final errors = <String>[];
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // 탭 우선, 없으면 콤마, 없으면 공백 다중
      final parts = line
          .split(RegExp(r'\t|,|\s{2,}'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (parts.length < 4) {
        // 헤더로 추정되는 첫 줄은 조용히 무시
        if (i == 0 && parts.any((p) => p.contains('학년') || p.contains('이름'))) {
          continue;
        }
        errors.add('${i + 1}행: 항목이 부족해요 ("$line")');
        continue;
      }

      final grade = int.tryParse(parts[0]);
      final classNum = int.tryParse(parts[1]);
      final studentNum = int.tryParse(parts[2]);
      final name = parts.sublist(3).join(' ').trim();

      if (grade == null || classNum == null || studentNum == null) {
        // 헤더 줄 (학년/반/번호가 숫자가 아님) → 무시
        if (i == 0) continue;
        errors.add('${i + 1}행: 학년·반·번호는 숫자여야 해요 ("$line")');
        continue;
      }
      if (name.isEmpty) {
        errors.add('${i + 1}행: 이름이 비었어요 ("$line")');
        continue;
      }
      rows.add(RosterDraftRow(
        grade: grade,
        classNum: classNum,
        studentNum: studentNum,
        name: name,
      ));
    }
    return (rows, errors);
  }
}
