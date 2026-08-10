import 'dart:async';

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
    // 백그라운드로 보내(await 안 함) — 미배포/지연/실패가 칭찬 완료를 막지 않게.
    unawaited(
      _c.functions.invoke('send-praise-push', body: {
        'student_id': studentUserId,
        'message': message,
      }).then((_) {}).catchError((_) {/* 푸시 실패는 무시 */}),
    );
    if (res is Map && res['praise_count'] != null) {
      return (res['praise_count'] as num).toInt();
    }
    return 0;
  }

  /// 교사가 여러 학생을 한 번에 칭찬. 실제 전송된 인원 수를 반환.
  /// 학급 전체처럼 여러 명에게 같은 한마디를 보낼 때 사용한다.
  Future<int> givePraiseBulk({
    required List<String> studentUserIds,
    required String message,
  }) async {
    final res = await _c.rpc('give_praise_bulk', params: {
      'p_student_ids': studentUserIds,
      'p_message': message,
    });
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '칭찬을 보내지 못했어요');
    }
    // 받은 학생들에게 푸시 (백그라운드 — 실패해도 칭찬은 이미 저장됨)
    for (final id in studentUserIds) {
      unawaited(
        _c.functions.invoke('send-praise-push', body: {
          'student_id': id,
          'message': message,
        }).then((_) {}).catchError((_) {}),
      );
    }
    return (m['sent'] as num?)?.toInt() ?? 0;
  }

  /// 학생: 내가 받은 칭찬 목록 (보낸 선생님 이름 포함).
  /// teacher_id가 auth.users를 참조해 조인이 안 되므로 RPC를 쓴다.
  Future<List<Praise>> fetchMyReceived({int limit = 50}) async {
    final rows = await _c.rpc('my_praises', params: {'p_limit': limit});
    return List<Map<String, dynamic>>.from(rows as List)
        .map(Praise.fromMap)
        .toList();
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
