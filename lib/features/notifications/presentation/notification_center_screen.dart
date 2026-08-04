import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../models/app_notification.dart';
import '../providers/notification_provider.dart';

/// 🔔 알림 센터 — 놓친 소식을 이력으로 확인한다.
/// 학생: 받은 칭찬·새 강화물·규칙 변경·새싹 성장
/// 교사: 교환 요청·라운지 소식·규칙 변경
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    // 화면을 열면 모두 읽음 처리 (배지 정리)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      markNotificationsRead(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myNotificationsProvider);
    final isTeacher = ref.watch(profileProvider).value?.isTeacher ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('🔔 알림',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myNotificationsProvider);
          await markNotificationsRead(ref);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text(translateError(e))),
            ),
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 90),
                    child: Column(
                      children: [
                        const Text('🔔', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 12),
                        Text('아직 도착한 소식이 없어요.',
                            style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                          isTeacher
                              ? '교환 요청·라운지 소식이 여기에 쌓여요.'
                              : '칭찬·새 강화물·새싹 성장 소식이 여기에 쌓여요.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _NotificationTile(n: list[i], isTeacher: isTeacher),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.isTeacher});
  final AppNotification n;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final route = n.routeFor(isTeacher: isTeacher);
    return Material(
      color: n.isRead ? AppColors.surface : const Color(0xFFF2F8EA),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: route == null ? null : () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!n.isRead)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            n.displayTitle,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight:
                                  n.isRead ? FontWeight.w700 : FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(n.relativeTime,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                    if ((n.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(n.body!,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5,
                              height: 1.45,
                              color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (route != null)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 홈 화면 우상단 종 아이콘 (안 읽은 개수 배지).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.route = '/student/notifications'});
  final String route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return GestureDetector(
      onTap: () => context.go(route),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_rounded,
            size: 26,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
          ),
          if (count > 0)
            Positioned(
              top: -3,
              right: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
