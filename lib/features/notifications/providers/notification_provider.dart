import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/app_notification.dart';

/// 내 알림 목록 (최신순).
final myNotificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  final rows = await SupabaseService.client
      .rpc('my_notifications', params: {'p_limit': 60});
  return (rows as List)
      .map((m) => AppNotification.fromMap(Map<String, dynamic>.from(m)))
      .toList();
});

/// 안 읽은 알림 개수 (홈 종 배지).
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final res = await SupabaseService.client.rpc('unread_notification_count');
  return (res as num?)?.toInt() ?? 0;
});

/// 모두 읽음 처리.
Future<void> markNotificationsRead(WidgetRef ref) async {
  await SupabaseService.client.rpc('mark_notifications_read');
  ref.invalidate(myNotificationsProvider);
  ref.invalidate(unreadNotificationCountProvider);
}

/// 우리 학교 새싹이 레벨업했는지 서버에 확인 — 올랐으면 학교 전체에 알림이 남는다.
/// 홈 진입 시 조용히 호출한다 (실패해도 무시).
Future<void> checkGrowthLevelUp(WidgetRef ref) async {
  try {
    final res = await SupabaseService.client.rpc('notify_growth_levelup');
    final m = Map<String, dynamic>.from(res as Map);
    if (m['leveled_up'] == true) {
      ref.invalidate(unreadNotificationCountProvider);
      ref.invalidate(myNotificationsProvider);
    }
  } catch (_) {
    // 알림은 부가 기능 — 조용히 무시
  }
}
