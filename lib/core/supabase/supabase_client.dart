import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    final rawUrl = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (rawUrl == null || rawUrl.isEmpty || anonKey == null || anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY가 .env에 설정되어 있지 않습니다.',
      );
    }
    // URL 정규화: 끝의 /rest/v1 또는 슬래시 자동 제거 (잘못된 환경변수 자동 정정)
    var url = rawUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    await Supabase.initialize(url: url, anonKey: anonKey.trim());
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
}
