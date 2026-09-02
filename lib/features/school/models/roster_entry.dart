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

  /// 전각 공백·줄바꿈 없는 공백 등을 보통 공백으로 통일한다.
  /// 엑셀·한글에서 복사하면 이런 글자가 섞여 들어와 구분자 판정을 망친다.
  static String _normalize(String s) => s
      .replaceAll(' ', ' ')
      .replaceAll('　', ' ')
      .replaceAll('﻿', '')
      .trim();

  /// '3학년' · '2반' · '14번' 처럼 단위가 붙어 있어도 숫자만 뽑는다.
  static int? _num(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  /// 공백 한 칸으로 구분된 줄: 앞의 숫자 셋을 떼고 나머지를 통째로 이름으로 본다.
  /// '3 2 14 스튜어트유민리차드' 같은 줄이 한 덩어리로 읽히던 문제를 막는다.
  static final _spaced = RegExp(
      r'^(\d+)\s*(?:학년)?\s+(\d+)\s*(?:반)?\s+(\d+)\s*(?:번)?\s+(.+)$');

  static (List<RosterDraftRow> rows, List<String> errors) parse(String raw) {
    final rows = <RosterDraftRow>[];
    final errors = <String>[];
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map(_normalize)
        .where((l) => l.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 구분자를 하나만 고른다. 여러 개를 한꺼번에 쓰면
      // 이름 안의 쉼표나 공백까지 잘려 나간다.
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else if (line.contains(',')) {
        parts = line.split(',');
      } else {
        final m = _spaced.firstMatch(line);
        parts = m == null
            ? line.split(RegExp(r'\s{2,}'))
            : [m[1]!, m[2]!, m[3]!, m[4]!];
      }
      parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

      if (parts.length < 4) {
        // 헤더로 추정되는 첫 줄은 조용히 무시
        if (i == 0 && parts.any((p) => p.contains('학년') || p.contains('이름'))) {
          continue;
        }
        errors.add('${i + 1}행: 항목이 부족해요 ("$line")');
        continue;
      }

      final grade = _num(parts[0]);
      final classNum = _num(parts[1]);
      final studentNum = _num(parts[2]);
      // 이름이 여러 칸에 나뉘어 있으면(성/이름 분리) 다시 붙인다.
      final name = parts.sublist(3).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

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
