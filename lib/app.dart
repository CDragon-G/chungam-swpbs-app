import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/back_handler.dart';
import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';

/// Global navigator key — used by JaramBackHandler to show SnackBars
/// without a BuildContext.
class BackHandlerKey {
  BackHandlerKey._();
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static GlobalKey<NavigatorState> get navigatorKey =>
      _navigatorKey ??= GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState>? _navigatorKey;
}

class PbsPlusApp extends ConsumerStatefulWidget {
  const PbsPlusApp({super.key});

  @override
  ConsumerState<PbsPlusApp> createState() => _PbsPlusAppState();
}

class _PbsPlusAppState extends ConsumerState<PbsPlusApp> {
  @override
  void initState() {
    super.initState();
    // Install the native back handler once the router is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = ref.read(routerProvider);
      JaramBackHandler.install(router: router);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '자람',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: BackHandlerKey.scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.notoSansKrTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      // 시스템 글꼴 확대 시에도 레이아웃이 깨지지 않게 확대 상한을 둔다.
      // (접근성 확대는 1.3배까지 존중, 그 이상은 클램프)
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.85,
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: router,
    );
  }
}
