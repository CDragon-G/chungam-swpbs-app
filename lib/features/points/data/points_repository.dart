import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/point_exchange.dart';
import '../models/point_store_item.dart';
import '../models/point_transaction.dart';
import '../models/school_leaderboard_entry.dart';

class PointsRepository {
  PointsRepository();

  SupabaseClient get _c => SupabaseService.client;

  // ── User balance & history ─────────────────────────────────
  Future<int> myBalance() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return 0;
    final res = await _c.rpc('get_user_points', params: {'p_user_id': uid});
    if (res == null) return 0;
    return (res as num).toInt();
  }

  Future<int> userBalance(String userId) async {
    final res = await _c.rpc('get_user_points', params: {'p_user_id': userId});
    if (res == null) return 0;
    return (res as num).toInt();
  }

  Future<List<PointTransaction>> myHistory({int limit = 50}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('point_transactions')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((m) => PointTransaction.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  // ── Store items ────────────────────────────────────────────
  Future<List<PointStoreItem>> fetchItems(
    String schoolId, {
    bool onlyActive = false,
  }) async {
    var query =
        _c.from('point_store_items').select().eq('school_id', schoolId);
    if (onlyActive) query = query.eq('is_active', true);
    final rows = await query.order('order_index');
    return rows
        .map((m) => PointStoreItem.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// 학생용: 전교 공통 상품 + 우리 반(grade/classNum) 상품만.
  Future<List<PointStoreItem>> fetchItemsForStudent({
    required String schoolId,
    required int? grade,
    required int? classNum,
  }) async {
    final classFilter = (grade != null && classNum != null)
        ? ',and(grade.eq.$grade,class_num.eq.$classNum)'
        : '';
    final rows = await _c
        .from('point_store_items')
        .select()
        .eq('school_id', schoolId)
        .eq('is_active', true)
        .or('grade.is.null$classFilter')
        .order('order_index');
    return rows
        .map((m) => PointStoreItem.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<PointStoreItem> createItem({
    required String schoolId,
    required String name,
    String? description,
    required int costPoints,
    int? stock,
    required int orderIndex,
    String emoji = '🎁',
    int? grade,
    int? classNum,
    String? createdByName,
    String itemType = 'individual',
    int? maxPerStudent,
  }) async {
    final uid = _c.auth.currentUser?.id;
    final row = await _c
        .from('point_store_items')
        .insert({
          'school_id': schoolId,
          'name': name,
          'description': description,
          'cost_points': costPoints,
          'stock': stock,
          'is_active': true,
          'order_index': orderIndex,
          'emoji': emoji,
          'grade': grade,
          'class_num': classNum,
          'created_by': uid,
          'created_by_name': createdByName,
          'item_type': itemType,
          'max_per_student': maxPerStudent,
        })
        .select()
        .single();
    return PointStoreItem.fromMap(row);
  }

  Future<PointStoreItem> updateItem(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final row = await _c
        .from('point_store_items')
        .update({...patch, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id)
        .select()
        .single();
    return PointStoreItem.fromMap(row);
  }

  Future<void> deleteItem(String id) async {
    await _c.from('point_store_items').delete().eq('id', id);
  }

  Future<void> reorderItems(List<PointStoreItem> items) async {
    for (var i = 0; i < items.length; i++) {
      await _c
          .from('point_store_items')
          .update({'order_index': i})
          .eq('id', items[i].id);
    }
  }

  // ── 함께 키우기 (단체 강화물) ──────────────────────────────
  /// 포인트를 보탠다. 남은 금액을 넘기면 남은 만큼만 차감된다.
  Future<GroupItemStatus> contribute({
    required String itemId,
    required int amount,
  }) async {
    final res = await _c.rpc('contribute_to_group_item',
        params: {'p_item_id': itemId, 'p_amount': amount});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '포인트를 보태지 못했어요');
    }
    return groupStatus(itemId);
  }

  Future<GroupItemStatus> groupStatus(String itemId) async {
    final res =
        await _c.rpc('group_item_status', params: {'p_item_id': itemId});
    return GroupItemStatus.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// 교사: 목표를 채운 강화물을 지급 완료로 처리.
  Future<void> fulfillGroupItem(String itemId) async {
    final res =
        await _c.rpc('fulfill_group_item', params: {'p_item_id': itemId});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '처리하지 못했어요');
    }
  }

  /// 교사: 취소하고 보탠 포인트를 전원에게 환불.
  Future<int> cancelGroupItem(String itemId) async {
    final res =
        await _c.rpc('cancel_group_item', params: {'p_item_id': itemId});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) {
      throw StateError(m['error'] as String? ?? '취소하지 못했어요');
    }
    return (m['refunded_users'] as num?)?.toInt() ?? 0;
  }

  // ── Exchanges ──────────────────────────────────────────────
  Future<String> requestExchange(String itemId) async {
    final res =
        await _c.rpc('request_exchange', params: {'p_item_id': itemId});
    return res as String;
  }

  Future<List<PointExchange>> myExchanges({int limit = 30}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('point_exchanges')
        .select()
        .eq('user_id', uid)
        .order('requested_at', ascending: false)
        .limit(limit);
    return rows
        .map((m) => PointExchange.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<PointExchange>> fetchSchoolExchanges(
    String schoolId, {
    String? status,
    int limit = 200,
  }) async {
    var query = _c
        .from('point_exchanges')
        .select()
        .eq('school_id', schoolId);
    if (status != null) query = query.eq('status', status);
    final rows =
        await query.order('requested_at', ascending: false).limit(limit);

    // Fetch profiles separately and merge in code.
    // (Direct join fails because point_exchanges.user_id → auth.users(id),
    //  not profiles.user_id, so PostgREST can't resolve the embed.)
    final userIds = <String>{
      for (final r in rows) r['user_id'] as String,
    }.toList();

    final profilesByUserId = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      final profileRows = await _c
          .from('profiles')
          .select('user_id, nickname, grade, class_num, student_num')
          .inFilter('user_id', userIds);
      for (final p in profileRows) {
        profilesByUserId[p['user_id'] as String] = p as Map<String, dynamic>;
      }
    }

    return rows.map((m) {
      final row = Map<String, dynamic>.from(m as Map);
      final profile = profilesByUserId[row['user_id']];
      if (profile != null) {
        row['profiles'] = profile; // PointExchange.fromMap reads this key
      }
      return PointExchange.fromMap(row);
    }).toList();
  }

  Future<void> fulfillExchange(String id, {String? note}) async {
    await _c.rpc('fulfill_exchange', params: {
      'p_exchange_id': id,
      'p_note': note,
    });
  }

  Future<void> cancelExchange(String id, {String? note}) async {
    await _c.rpc('cancel_exchange', params: {
      'p_exchange_id': id,
      'p_note': note,
    });
  }

  // ── School leaderboard ─────────────────────────────────────
  Future<List<SchoolLeaderboardEntry>> fetchLeaderboard(
      {int limit = 50}) async {
    final rows = await _c
        .from('school_leaderboard')
        .select()
        .order('school_score', ascending: false)
        .limit(limit);
    return rows
        .map((m) => SchoolLeaderboardEntry.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<SchoolLeaderboardEntry?> fetchMySchool(String schoolId) async {
    final row = await _c
        .from('school_leaderboard')
        .select()
        .eq('id', schoolId)
        .maybeSingle();
    if (row == null) return null;
    return SchoolLeaderboardEntry.fromMap(row);
  }

  // ── Teacher: per-student aggregates ────────────────────────
  Future<Map<String, int>> fetchStudentBalances(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await _c
        .from('point_transactions')
        .select('user_id, amount')
        .inFilter('user_id', userIds);
    final balances = <String, int>{};
    for (final r in rows) {
      final uid = r['user_id'] as String;
      final amt = (r['amount'] as num).toInt();
      balances[uid] = (balances[uid] ?? 0) + amt;
    }
    return balances;
  }

  // 자기점검 포인트는 서버(submit_checkin)가 직접 지급한다.
  // 앱에서 부를 수 있으면 날짜·계정을 조작할 수 있어 권한을 회수했다.
}
