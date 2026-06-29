import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/praise.dart';

class PraiseRepository {
  PraiseRepository();

  SupabaseClient get _c => SupabaseService.client;

  String _myId() {
    final u = _c.auth.currentUser;
    if (u == null) throw StateError('로그인 상태가 아닙니다.');
    return u.id;
  }

  /// 교사가 학생을 칭찬. 칭찬 횟수를 반환.
  Future<int> givePraise({
    required String studentUserId,
    required String message,
  }) async {
    final res = await _c.rpc('give_praise', params: {
      'p_student_user_id': studentUserId,
      'p_message': message,
    });
    // 칭찬받은 학생에게 푸시 발송 (Edge Function).
    // 미배포/실패해도 칭찬 자체는 정상 처리되도록 무시.
    try {
      await _c.functions.invoke('send-praise-push', body: {
        'student_id': studentUserId,
        'message': message,
      });
    } catch (_) {/* 푸시 실패는 무시 */}
    if (res is Map && res['praise_count'] != null) {
      return (res['praise_count'] as num).toInt();
    }
    return 0;
  }

  /// 학생: 내가 받은 칭찬 목록.
  Future<List<Praise>> fetchMyReceived({int limit = 50}) async {
    final rows = await _c
        .from('praise')
        .select()
        .eq('student_id', _myId())
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows).map(Praise.fromMap).toList();
  }

  /// 학생: 안 읽은 칭찬 개수.
  Future<int> unreadCount() async {
    final rows = await _c
        .from('praise')
        .select('id')
        .eq('student_id', _myId())
        .eq('is_read', false);
    return rows.length;
  }

  /// 학생: 받은 칭찬 모두 읽음 처리.
  Future<void> markAllRead() async {
    await _c.rpc('mark_praise_read');
  }
}
