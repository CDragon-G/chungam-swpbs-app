/// 🔔 알림 센터 항목.
class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.route,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String type; // praise|store_item|rule|growth|exchange|lounge|notice
  final String title;
  final String? body;
  final String? route;
  final DateTime createdAt;
  final bool isRead;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: m['type'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        route: m['route'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        isRead: m['is_read'] as bool? ?? false,
      );

  /// 제목 앞의 이모지를 뗀 텍스트.
  /// 알림 제목은 푸시 알림용으로 이모지를 포함하는데, 알림 센터는
  /// 왼쪽에 아이콘을 따로 그리므로 중복을 없앤다.
  String get displayTitle =>
      title.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();

  String get emoji => switch (type) {
        'praise' => '💚',
        'store_item' => '🎁',
        'rule' => '📖',
        'growth' => '🌱',
        'exchange' => '🛍️',
        'lounge' => '🎓',
        _ => '📢',
      };

  /// 역할에 맞는 이동 경로 (없으면 null).
  String? routeFor({required bool isTeacher}) => switch (type) {
        'praise' => isTeacher ? null : '/student/mypage',
        'store_item' => isTeacher ? '/teacher/store' : '/student/store',
        'rule' => isTeacher ? '/teacher/rules' : null,
        'exchange' => isTeacher ? '/teacher/store' : null,
        'lounge' => isTeacher ? '/teacher/lounge' : null,
        'growth' => isTeacher ? '/teacher/home' : '/student/home',
        _ => isTeacher ? '/teacher/announce' : '/student/store',
      };

  /// '방금 전' · '3시간 전' · '2일 전' · 'M월 d일'
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${createdAt.month}월 ${createdAt.day}일';
  }
}
