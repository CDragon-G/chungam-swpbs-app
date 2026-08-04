import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/notifications/fcm_service.dart';
import '../../../core/notifications/notifications_service.dart';
import '../../../core/notifications/reminder_prefs.dart';

/// 🔔 알림 권한 안내 — 첫 실행 시 한 번만.
/// OS 권한 창을 곧바로 띄우지 않고, 왜 필요한지 먼저 설명한다
/// (거절률을 낮추는 표준 패턴 — pre-permission prompt).
class NotificationConsent {
  NotificationConsent._();

  static const _kAsked = 'notif_consent_asked_v1';

  static Future<void> showIfFirstLaunch(
    BuildContext context, {
    required bool isTeacher,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kAsked) ?? false) return;
    if (!context.mounted) return;

    // ⚠️ 다이얼로그 안에서는 반드시 dialogCtx로 pop 할 것.
    // 바깥 context를 쓰면 ShellRoute 환경에서 다이얼로그가 아니라
    // 화면 자체가 닫혀 검은 화면이 된다.
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('🔔 알림을 받아볼까요?',
            style: GoogleFonts.notoSansKr(
                fontSize: 18, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTeacher
                  ? '이런 소식을 놓치지 않게 알려드려요.'
                  : '이런 소식을 놓치지 않게 알려줄게요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...(isTeacher
                    ? const [
                        ('🛍️', '학생의 강화물 교환 요청'),
                        ('🎁', '교사 라운지 새 강화물·클래스'),
                        ('📖', '우리 학교 규칙 변경'),
                        ('🌱', '우리 학교 새싹 성장'),
                      ]
                    : const [
                        ('💚', '선생님께 받은 칭찬'),
                        ('🎁', '새로 등록된 강화물'),
                        ('✅', '오늘 자기점검 리마인더'),
                        ('🌱', '우리 학교 새싹 성장'),
                      ])
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text(e.$1, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(e.$2,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    )),
            const SizedBox(height: 10),
            Text('나중에 설정에서 언제든 바꿀 수 있어요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('나중에',
                style: GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('알림 받기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    await p.setBool(_kAsked, true);
    if (agreed != true) return;

    // 동의했을 때만 OS 권한 요청 + 푸시 토큰 등록.
    // 권한 거부·토큰 발급 실패가 홈 화면을 막지 않도록 개별 보호.
    try {
      await NotificationsService.requestPermission();
      await FcmService.initialize();
      if (!isTeacher) {
        await ReminderPrefs.ensureDefaultOnForStudent();
      }
    } catch (_) {
      // 알림은 부가 기능 — 실패해도 앱 사용에 지장 없음
    }
  }
}
