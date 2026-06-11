import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_select_screen.dart';
import '../../features/auth/presentation/student_signup_screen.dart';
import '../../features/auth/presentation/teacher_signup_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/checkin/presentation/checkin_result_screen.dart';
import '../../features/checkin/presentation/checkin_screen.dart';
import '../../features/points/presentation/student_store_screen.dart';
import '../../features/points/presentation/teacher_store_screen.dart';
import '../../features/student/presentation/badges_screen.dart';
import '../../features/student/presentation/compare_screen.dart';
import '../../features/student/presentation/my_page_screen.dart';
import '../../features/student/presentation/student_home_screen.dart';
import '../../features/teacher/presentation/announcement_screen.dart';
import '../../features/teacher/presentation/dashboard_screen.dart';
import '../../features/teacher/presentation/rule_editor_screen.dart';
import '../../features/teacher/presentation/student_list_screen.dart';
import '../../features/teacher/presentation/teacher_home_screen.dart';
import '../../features/teacher/presentation/teacher_management_screen.dart';
import '../../shared/providers/profile_provider.dart';
import '../../shared/widgets/pbs_bottom_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  return GoRouter(
    initialLocation: '/welcome',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/welcome') ||
          loc.startsWith('/login') ||
          loc.startsWith('/signup');

      final authValue = ref.read(authStateProvider);
      final user = authValue.value;
      if (user == null) {
        return isAuthRoute ? null : '/welcome';
      }

      final profileAsync = ref.read(profileProvider);
      if (profileAsync.isLoading) return null;
      final profile = profileAsync.value;

      // signed in but no profile row yet — allow signup screens to finish
      if (profile == null) return isAuthRoute ? null : '/signup-select';

      if (isAuthRoute) {
        return profile.role == 'teacher' ? '/teacher/home' : '/student/home';
      }
      if (profile.role == 'student' && loc.startsWith('/teacher')) {
        return '/student/home';
      }
      if (profile.role == 'teacher' && loc.startsWith('/student')) {
        return '/teacher/home';
      }
      return null;
    },
    routes: [
      // Auth
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup-select', builder: (_, __) => const SignupSelectScreen()),
      GoRoute(path: '/signup/teacher', builder: (_, __) => const TeacherSignupScreen()),
      GoRoute(path: '/signup/student', builder: (_, __) => const StudentSignupScreen()),

      // Student shell
      ShellRoute(
        builder: (context, state, child) =>
            StudentShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/student/home', builder: (_, __) => const StudentHomeScreen()),
          GoRoute(path: '/student/checkin', builder: (_, __) => const CheckinScreen()),
          GoRoute(path: '/student/checkin/result', builder: (_, __) => const CheckinResultScreen()),
          GoRoute(path: '/student/mypage', builder: (_, __) => const MyPageScreen()),
          GoRoute(path: '/student/badges', builder: (_, __) => const BadgesScreen()),
          GoRoute(path: '/student/store', builder: (_, __) => const StudentStoreScreen()),
          GoRoute(path: '/student/points-history', builder: (_, __) => const StudentStoreScreen()),
          GoRoute(path: '/student/compare', builder: (_, __) => const CompareScreen()),
        ],
      ),

      // Teacher shell
      ShellRoute(
        builder: (context, state, child) =>
            TeacherShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/teacher/home', builder: (_, __) => const TeacherHomeScreen()),
          GoRoute(path: '/teacher/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/teacher/students', builder: (_, __) => const StudentListScreen()),
          GoRoute(path: '/teacher/rules', builder: (_, __) => const RuleEditorScreen()),
          GoRoute(path: '/teacher/store', builder: (_, __) => const TeacherStoreScreen()),
          GoRoute(path: '/teacher/announce', builder: (_, __) => const AnnouncementScreen()),
          GoRoute(path: '/teacher/permissions', builder: (_, __) => const TeacherManagementScreen()),
        ],
      ),
    ],
  );
});

/// Bridge Riverpod -> GoRouter's refreshListenable.
/// `notifyListeners` fires whenever auth or profile state changes; the GoRouter
/// itself stays the same instance, so navigation stack is preserved.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
    _ref.listen(profileProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}
