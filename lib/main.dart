import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/notifications_service.dart';
import 'core/notifications/reminder_prefs.dart';
import 'core/supabase/supabase_client.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Google Fonts: allow runtime fetching (default) BUT silently swallow errors
  // when network blocks gstatic.com. App will fall back to system fonts.
  GoogleFonts.config.allowRuntimeFetching = true;

  // Suppress noisy google_fonts errors that get rethrown asynchronously.
  // These are non-fatal: the text still renders with a system fallback.
  final origFlutterErr = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('google_fonts') ||
        msg.contains('fonts.gstatic.com') ||
        msg.contains('NotoSansKR')) {
      return; // swallow
    }
    origFlutterErr?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    final s = error.toString();
    if (s.contains('google_fonts') ||
        s.contains('fonts.gstatic.com') ||
        s.contains('NotoSansKR')) {
      return true; // handled (swallowed)
    }
    debugPrint('[Unhandled] $error\n$stack');
    return false;
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await dotenv.load();
  await initializeDateFormatting('ko_KR');
  await SupabaseService.initialize();
  await NotificationsService.initialize();
  await ReminderPrefs.reschedule(); // 일일 리마인더 재예약 보정

  // Firebase + FCM 원격 푸시
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FcmService.initialize();
  } catch (e) {
    debugPrint('[main] Firebase 초기화 실패(무시하고 계속): $e');
  }

  runApp(const ProviderScope(child: PbsPlusApp()));
}
