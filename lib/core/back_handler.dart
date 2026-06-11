import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app.dart' show BackHandlerKey;
import 'constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Static state shared across rebuilds.
class _BackState {
  static DateTime? lastBack;
}

class JaramBackHandler {
  JaramBackHandler._();

  static const _channel = MethodChannel('com.jaram.app/back');

  /// Call once from main() after runApp() to register the handler.
  static void install({required GoRouter router}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onBackPressed') return false;
      return _handleBack(router);
    });
  }

  /// Returns true if Dart handled the back (Android should NOT exit).
  /// Returns false to let Android perform default behavior (usually exit).
  static Future<bool> _handleBack(GoRouter router) async {
    final loc = router.routerDelegate.currentConfiguration.uri.path;
    debugPrint('[BackHandler] pressed | location=$loc');

    String? homeRoute;
    if (loc.startsWith('/student/')) homeRoute = '/student/home';
    if (loc.startsWith('/teacher/')) homeRoute = '/teacher/home';

    // Not in a shell (auth screens, etc) → allow default
    if (homeRoute == null) {
      debugPrint('[BackHandler] not in shell → allow default');
      return false;
    }

    final isOnHome = loc == homeRoute;

    // Sub-tab → bounce to home tab
    if (!isOnHome) {
      debugPrint('[BackHandler] sub-tab → go home');
      router.go(homeRoute);
      return true;
    }

    // On home: double-back to exit
    final now = DateTime.now();
    if (_BackState.lastBack != null &&
        now.difference(_BackState.lastBack!) < const Duration(seconds: 2)) {
      debugPrint('[BackHandler] double-back → exit');
      _BackState.lastBack = null;
      return false; // let Android exit
    }

    _BackState.lastBack = now;
    debugPrint('[BackHandler] first back on home → toast');
    final messenger = BackHandlerKey.scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('한 번 더 뒤로 가기를 누르시면 종료됩니다'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            backgroundColor: AppColors.textPrimary,
          ),
        );
    }
    return true;
  }
}
