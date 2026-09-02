import '../../core/supabase/supabase_client.dart';

/// 규칙 건의함 — 학생이 올리고 관리자 선생님만 읽는다.
class SuggestionsRepository {
  final _c = SupabaseService.client;

  Future<void> submit({required String body, String? space}) async {
    final res = await _c.rpc('submit_rule_suggestion',
        params: {'p_body': body, 'p_space': space});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '보내지 못했어요');
    }
  }

  /// 관리자 전용 목록.
  Future<List<RuleSuggestion>> list({int limit = 200}) async {
    final res =
        await _c.rpc('rule_suggestion_list', params: {'p_limit': limit});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '불러오지 못했어요');
    }
    return ((m['items'] as List?) ?? const [])
        .map((e) => RuleSuggestion.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> setStatus(String id, String status, {String? note}) async {
    await _c.from('rule_suggestions').update({
      'status': status,
      if (note != null) 'admin_note': note,
    }).eq('id', id);
  }

  /// 내가 낸 건의 (학생 화면에서 확인용).
  Future<List<RuleSuggestion>> mine() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('rule_suggestions')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(20);
    return rows.map((m) => RuleSuggestion.fromMap(m)).toList();
  }
}

class RuleSuggestion {
  RuleSuggestion({
    required this.id,
    required this.body,
    required this.status,
    required this.createdAt,
    this.space,
    this.adminNote,
    this.nickname,
    this.grade,
    this.classNum,
    this.studentNum,
  });

  final String id;
  final String body;
  final String status; // new | read | accepted | declined
  final DateTime createdAt;
  final String? space;
  final String? adminNote;

  // 관리자 목록에서만 채워진다
  final String? nickname;
  final int? grade;
  final int? classNum;
  final int? studentNum;

  String get who => (grade == null || classNum == null)
      ? (nickname ?? '')
      : '$grade학년 $classNum반 ${studentNum ?? 0}번 ${nickname ?? ''}';

  String get statusLabel => switch (status) {
        'new' => '새 건의',
        'read' => '확인함',
        'accepted' => '반영',
        'declined' => '보류',
        _ => status,
      };

  factory RuleSuggestion.fromMap(Map<String, dynamic> m) => RuleSuggestion(
        id: m['id'] as String,
        body: m['body'] as String,
        status: (m['status'] as String?) ?? 'new',
        createdAt: DateTime.parse(m['created_at'] as String),
        space: m['space'] as String?,
        adminNote: m['admin_note'] as String?,
        nickname: m['nickname'] as String?,
        grade: (m['grade'] as num?)?.toInt(),
        classNum: (m['class_num'] as num?)?.toInt(),
        studentNum: (m['student_num'] as num?)?.toInt(),
      );
}
