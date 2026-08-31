import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../supabase/supabase_client.dart';

/// 스토어에 올라간 버전과 지금 깔린 버전을 비교한 결과.
class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.storeUrl,
    required this.updateAvailable,
    required this.force,
  });

  /// 지금 기기에 깔린 버전 (예: '0.18.0')
  final String current;

  /// 스토어 최신 버전
  final String latest;
  final String storeUrl;

  /// 최신 버전이 아니다 — 안내 팝업을 띄운다.
  final bool updateAvailable;

  /// 최소 지원 버전보다 낮다 — 업데이트 전에는 계속 쓸 수 없다.
  final bool force;

  static const none = UpdateInfo(
    current: '',
    latest: '',
    storeUrl: '',
    updateAvailable: false,
    force: false,
  );
}

/// 앱을 켤 때 최신 버전인지 확인한다.
/// 서버의 app_releases 표를 기준으로 하므로, 스토어 심사가 끝난 뒤
/// 그 표만 고치면 사용자에게 업데이트 안내가 나간다.
class UpdateService {
  UpdateService._();

  static Future<UpdateInfo> check() async {
    // 웹·데스크톱에는 스토어가 없다.
    if (kIsWeb) return UpdateInfo.none;
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : null;
    if (platform == null) return UpdateInfo.none;

    try {
      final info = await PackageInfo.fromPlatform();
      final res = await SupabaseService.client.rpc(
        'app_update_check',
        params: {'p_platform': platform, 'p_version': info.version},
      );
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) return UpdateInfo.none;

      return UpdateInfo(
        current: info.version,
        latest: (m['latest'] as String?) ?? '',
        storeUrl: (m['store_url'] as String?) ?? '',
        updateAvailable: (m['update_available'] as bool?) ?? false,
        force: (m['force'] as bool?) ?? false,
      );
    } catch (e) {
      // 버전 확인 실패가 앱 사용을 막아서는 안 된다.
      debugPrint('[UpdateService] $e');
      return UpdateInfo.none;
    }
  }
}
