import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../supabase/supabase_client.dart';

/// FCM 백그라운드 메시지 핸들러 (top-level 함수여야 함).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드/종료 상태에서 받은 푸시는 OS가 알림으로 표시.
  // 추가 처리가 필요하면 여기서. (현재는 표시만으로 충분)
  debugPrint('[FCM bg] ${message.notification?.title}');
}

/// Firebase Cloud Messaging 원격 푸시 서비스.
/// - 권한 요청, 토큰 발급, Supabase 등록, 포그라운드 표시를 담당.
class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'jaram_push';
  static const _channelName = '자람 알림';

  /// 앱 시작 시 1회 호출 (Firebase.initializeApp 이후).
  static Future<void> initialize() async {
    // 알림 권한 요청 (iOS는 팝업, Android 13+도 필요)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 안드로이드 알림 채널 등록 (포그라운드 표시용)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '칭찬·점검·공지 알림',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // iOS 포그라운드에서도 배너 표시
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 포그라운드 메시지 → 로컬 알림으로 직접 표시
    FirebaseMessaging.onMessage.listen(_showForeground);
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// 로그인 후 호출: 이 기기의 FCM 토큰을 Supabase에 등록.
  /// 같은 사용자가 여러 기기를 써도 각각 등록됨.
  static Future<void> registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _save(token);
      // 토큰 갱신 시 자동 재등록
      _messaging.onTokenRefresh.listen(_save);
    } catch (e) {
      debugPrint('[FCM] registerToken 실패: $e');
    }
  }

  static Future<void> _save(String token) async {
    try {
      await SupabaseService.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('[FCM] 토큰 저장 실패: $e');
    }
  }
}
