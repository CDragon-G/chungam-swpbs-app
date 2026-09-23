import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/providers/profile_provider.dart';

class _QuickItem {
  const _QuickItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    this.adminOnly = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String route;
  final bool adminOnly;
}

/// 대시보드 맨 위 바로가기 — 아이콘 한 줄로 모아 둔다.
/// 예전에는 화면 맨 아래에 긴 버튼이 5개 쌓여 있어서 스크롤해야 보였다.
class DashboardQuickMenu extends ConsumerWidget {
  const DashboardQuickMenu({super.key});

  static const _items = [
    _QuickItem(
      label: '보낸 칭찬',
      icon: Icons.favorite_rounded,
      color: Color(0xFFEF4444),
      route: '/teacher/praise-sent',
    ),
    _QuickItem(
      label: '칭찬 우체통',
      icon: Icons.markunread_mailbox_rounded,
      color: Color(0xFFDB2777),
      route: '/teacher/praise-mail',
    ),
    _QuickItem(
      label: '규칙 현황',
      icon: Icons.rule_rounded,
      color: Color(0xFF2563EB),
      route: '/teacher/rule-stats',
    ),
    _QuickItem(
      label: '담임반',
      icon: Icons.groups_rounded,
      color: Color(0xFF0D9488),
      route: '/teacher/homeroom',
    ),
    _QuickItem(
      label: '학맞통 안건',
      icon: Icons.extension_rounded,
      color: Color(0xFFB91C1C),
      route: '/teacher/support',
      adminOnly: true,
    ),
    _QuickItem(
      label: '건의함',
      icon: Icons.mark_email_unread_rounded,
      color: Color(0xFFD97706),
      route: '/teacher/suggestions',
      adminOnly: true,
    ),
    _QuickItem(
      label: '포인트 설정',
      icon: Icons.tune_rounded,
      color: Color(0xFF7C3AED),
      route: '/teacher/point-rules',
      adminOnly: true,
    ),
    _QuickItem(
      label: '로그인 도움',
      icon: Icons.key_rounded,
      color: Color(0xFF0369A1),
      route: '/teacher/account-help',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;
    final items =
        _items.where((i) => isAdmin || !i.adminOnly).toList(growable: false);

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap * 3) / 4; // 한 줄에 4개
        return Wrap(
          spacing: gap,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: w,
                child: _QuickButton(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.item});
  final _QuickItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(item.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(item.icon, size: 23, color: item.color),
            ),
            const SizedBox(height: 5),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
