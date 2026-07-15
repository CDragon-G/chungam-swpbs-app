import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/lounge_models.dart';

/// 내 교사 포인트 잔액.
final teacherPointBalanceProvider = FutureProvider<int>((ref) async {
  final res = await SupabaseService.client.rpc('teacher_point_balance');
  return (res as num?)?.toInt() ?? 0;
});

/// 우리 학교 교사 강화물 목록.
final teacherRewardItemsProvider =
    FutureProvider<List<TeacherRewardItem>>((ref) async {
  final rows = await SupabaseService.client
      .from('teacher_store_items')
      .select()
      .eq('is_active', true)
      .order('cost_points');
  return (rows as List)
      .map((m) => TeacherRewardItem.fromMap(Map<String, dynamic>.from(m)))
      .toList();
});

/// 원데이클래스 목록 (+개설자 이름·신청 인원·내 신청 여부).
final teacherClassesProvider =
    FutureProvider<List<TeacherClassInfo>>((ref) async {
  final client = SupabaseService.client;
  final uid = client.auth.currentUser?.id;
  final rows = await client
      .from('teacher_classes')
      .select()
      .neq('status', 'cancelled')
      .order('created_at', ascending: false)
      .limit(30);
  var classes = (rows as List)
      .map((m) => TeacherClassInfo.fromMap(Map<String, dynamic>.from(m)))
      .toList();
  if (classes.isEmpty) return classes;

  final ids = classes.map((c) => c.id).toList();
  final enrolls = await client
      .from('class_enrollments')
      .select('class_id, teacher_id')
      .inFilter('class_id', ids);
  final enrollList = (enrolls as List).cast<Map<String, dynamic>>();

  // 개설자 + 신청자 이름
  final userIds = <String>{
    ...classes.map((c) => c.hostId),
    ...enrollList.map((e) => e['teacher_id'] as String),
  }.toList();
  final profiles = await client
      .from('profiles')
      .select('user_id, nickname')
      .inFilter('user_id', userIds);
  final nameOf = {
    for (final p in (profiles as List).cast<Map<String, dynamic>>())
      p['user_id'] as String: p['nickname'] as String
  };

  classes = classes.map((c) {
    final mine = enrollList
        .where((e) => e['class_id'] == c.id)
        .map((e) => e['teacher_id'] as String)
        .toList();
    return c.copyWith(
      hostName: nameOf[c.hostId],
      enrolledCount: mine.length,
      enrolledNames:
          mine.map((id) => nameOf[id] ?? '선생님').toList(),
      myEnrolled: uid != null && mine.contains(uid),
    );
  }).toList();
  return classes;
});

/// 내 포인트 적립·사용 내역.
final myTeacherTxProvider = FutureProvider<List<TeacherPointTx>>((ref) async {
  final uid = SupabaseService.client.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await SupabaseService.client
      .from('teacher_point_transactions')
      .select('points, source, created_at')
      .eq('teacher_id', uid)
      .order('created_at', ascending: false)
      .limit(40);
  return (rows as List)
      .map((m) => TeacherPointTx.fromMap(Map<String, dynamic>.from(m)))
      .toList();
});

/// 내 교환 신청 내역.
final myTeacherExchangesProvider =
    FutureProvider<List<TeacherExchange>>((ref) async {
  final uid = SupabaseService.client.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await SupabaseService.client
      .from('teacher_exchanges')
      .select()
      .eq('teacher_id', uid)
      .order('requested_at', ascending: false)
      .limit(20);
  return (rows as List)
      .map((m) => TeacherExchange.fromMap(Map<String, dynamic>.from(m)))
      .toList();
});

/// (관리자) 승인 대기 교환 목록 — 신청 교사 이름 포함.
final pendingTeacherExchangesProvider =
    FutureProvider<List<TeacherExchange>>((ref) async {
  final client = SupabaseService.client;
  final rows = await client
      .from('teacher_exchanges')
      .select()
      .eq('status', 'pending')
      .order('requested_at');
  var list = (rows as List)
      .map((m) => TeacherExchange.fromMap(Map<String, dynamic>.from(m)))
      .toList();
  if (list.isEmpty) return list;
  final profiles = await client
      .from('profiles')
      .select('user_id, nickname')
      .inFilter('user_id', list.map((e) => e.teacherId).toSet().toList());
  final nameOf = {
    for (final p in (profiles as List).cast<Map<String, dynamic>>())
      p['user_id'] as String: p['nickname'] as String
  };
  return list.map((e) => e.withName(nameOf[e.teacherId])).toList();
});

/// 라운지 액션 저장소.
class LoungeRepository {
  final _client = SupabaseService.client;

  Future<String?> exchangeItem(String itemId) async {
    final res = await _client
        .rpc('teacher_exchange_item', params: {'p_item_id': itemId});
    final m = Map<String, dynamic>.from(res as Map);
    return m['ok'] == true ? null : m['error'] as String?;
  }

  Future<String?> cancelExchange(String exchangeId) async {
    final res = await _client
        .rpc('teacher_exchange_cancel', params: {'p_exchange_id': exchangeId});
    final m = Map<String, dynamic>.from(res as Map);
    return m['ok'] == true ? null : m['error'] as String?;
  }

  Future<void> fulfillExchange(String exchangeId) => _client
      .from('teacher_exchanges')
      .update({
        'status': 'fulfilled',
        'fulfilled_at': DateTime.now().toUtc().toIso8601String(),
        'fulfilled_by': _client.auth.currentUser!.id,
      })
      .eq('id', exchangeId);

  Future<void> addItem({
    required String schoolId,
    required String name,
    String? description,
    required int costPoints,
    int? stock,
  }) =>
      _client.from('teacher_store_items').insert({
        'school_id': schoolId,
        'name': name,
        'description': description,
        'cost_points': costPoints,
        'stock': stock,
        'created_by': _client.auth.currentUser!.id,
      });

  Future<void> deactivateItem(String itemId) => _client
      .from('teacher_store_items')
      .update({'is_active': false}).eq('id', itemId);

  Future<void> openClass({
    required String schoolId,
    required String title,
    String? description,
    required int costPoints,
    required int minParticipants,
    int? maxParticipants,
    int? durationMinutes,
    DateTime? scheduledAt,
    String? location,
  }) =>
      _client.from('teacher_classes').insert({
        'school_id': schoolId,
        'host_id': _client.auth.currentUser!.id,
        'title': title,
        'description': description,
        'cost_points': costPoints,
        'min_participants': minParticipants,
        'max_participants': maxParticipants,
        'duration_minutes': durationMinutes,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'location': location,
      });

  Future<String?> enrollClass(String classId) async {
    final res = await _client
        .rpc('enroll_teacher_class', params: {'p_class_id': classId});
    final m = Map<String, dynamic>.from(res as Map);
    return m['ok'] == true ? null : m['error'] as String?;
  }

  Future<String?> cancelEnrollment(String classId) async {
    final res = await _client
        .rpc('cancel_class_enrollment', params: {'p_class_id': classId});
    final m = Map<String, dynamic>.from(res as Map);
    return m['ok'] == true ? null : m['error'] as String?;
  }

  Future<String?> cancelClass(String classId) async {
    final res = await _client
        .rpc('cancel_teacher_class', params: {'p_class_id': classId});
    final m = Map<String, dynamic>.from(res as Map);
    return m['ok'] == true ? null : m['error'] as String?;
  }
}

final loungeRepositoryProvider = Provider((ref) => LoungeRepository());

/// 라운지 화면 전체 새로고침.
void invalidateLounge(WidgetRef ref) {
  ref.invalidate(teacherPointBalanceProvider);
  ref.invalidate(teacherRewardItemsProvider);
  ref.invalidate(teacherClassesProvider);
  ref.invalidate(myTeacherTxProvider);
  ref.invalidate(myTeacherExchangesProvider);
  ref.invalidate(pendingTeacherExchangesProvider);
}
