import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

class StudentShell extends StatelessWidget {
  const StudentShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const _items = [
    _NavItem('/student/home', '홈', Icons.home_rounded),
    _NavItem('/student/checkin', '점검', Icons.check_circle_outline_rounded),
    _NavItem('/student/store', '상점', Icons.shopping_bag_rounded),
    _NavItem('/student/mypage', '마이', Icons.person_rounded),
    _NavItem('/student/compare', '비교', Icons.bar_chart_rounded),
  ];

  @override
  Widget build(BuildContext context) => _Shell(
        items: _items,
        location: location,
        color: AppColors.studentGreen,
        child: child,
      );
}

class TeacherShell extends StatelessWidget {
  const TeacherShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const _items = [
    _NavItem('/teacher/home', '홈', Icons.home_rounded),
    _NavItem('/teacher/dashboard', '대시보드', Icons.dashboard_rounded),
    _NavItem('/teacher/rules', '규칙', Icons.rule_rounded),
    _NavItem('/teacher/store', '상점', Icons.shopping_bag_rounded),
    _NavItem('/teacher/announce', '공지', Icons.campaign_rounded),
  ];

  @override
  Widget build(BuildContext context) => _Shell(
        items: _items,
        location: location,
        color: AppColors.teacherNavy,
        child: child,
      );
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.items,
    required this.location,
    required this.child,
    required this.color,
  });

  final List<_NavItem> items;
  final String location;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final idx = items.indexWhere((it) => location.startsWith(it.path));
    // Back handling is done at MaterialApp level (see _AppBackHandler in app.dart).
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx < 0 ? 0 : idx,
        onDestinationSelected: (i) => context.go(items[i].path),
        backgroundColor: AppColors.surface,
        indicatorColor: color.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : AppColors.textSecondary,
          );
        }),
        destinations: [
          for (final it in items)
            NavigationDestination(
              icon: Icon(it.icon, color: AppColors.textSecondary),
              selectedIcon: Icon(it.icon, color: color),
              label: it.label,
            ),
        ],
      ),
    );
  }
}
