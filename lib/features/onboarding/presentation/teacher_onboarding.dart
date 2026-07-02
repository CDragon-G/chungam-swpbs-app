import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

const _kTeacherOnboardingKey = 'teacher_onboarding_done_v1';

/// 교사가 처음 접속했을 때 자람 활용법을 안내하는 캐로셀.
/// 학생 온보딩과 별개 키로 관리한다.
class TeacherOnboarding {
  TeacherOnboarding._();
  static bool _busy = false;

  static Future<void> showIfFirstLaunch(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kTeacherOnboardingKey) == true) return;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _TeacherOnboardingDialog(),
      );
      await prefs.setBool(_kTeacherOnboardingKey, true);
    } finally {
      _busy = false;
    }
  }

  /// 설정 등에서 "다시 보기"로 강제 노출.
  static Future<void> showAlways(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _TeacherOnboardingDialog(),
      );
}

class _Notice {
  const _Notice(this.emoji, this.text);
  final String emoji;
  final String text;
}

class _TPage {
  const _TPage({
    required this.emoji,
    required this.subtitle,
    required this.title,
    required this.body,
    required this.color,
    this.researchNote,
    this.notice,
    this.bullets,
    this.warning,
    this.ctaLabel,
    this.ctaRoute,
  });

  final String emoji;
  final String subtitle;
  final String title;
  final String body;
  final Color color;
  final String? researchNote;
  final _Notice? notice;
  final List<String>? bullets;
  final String? warning;
  final String? ctaLabel;
  final String? ctaRoute;
}

const _pages = <_TPage>[
  _TPage(
    emoji: '🌱',
    subtitle: '교사 시작 가이드',
    title: '자람으로 SWPBS를 시작해요',
    body: '자람은 학교차원 긍정적 행동지원(SWPBS)을 한 곳에서 실행하도록 돕습니다.\n\n'
        '① 규칙 세우기 → ② 매일 긍정적 강화 → ③ 지원이 필요한 학생 발견,\n'
        '이 3단계를 차례로 안내할게요.',
    color: AppColors.studentGreen,
  ),
  _TPage(
    emoji: '📋',
    subtitle: 'STEP 1 · 가장 중요한 첫걸음',
    title: '우리 학교 규칙부터 세워요',
    body: '3~4월 초, 학급자치 시간을 활용해 학생과 교사가 함께 규칙을 정하세요.\n\n'
        "규칙은 '복도에서 뛰지 않기'(✕)가 아니라 "
        "'복도에서는 걸어다녀요'(○)처럼 긍정문으로 세워야 합니다.\n\n"
        '명확하고 지킬 수 있는 약속이 자람 활용의 첫걸음이에요.',
    researchNote: '💡 긍정문으로 표현된 명확한 규칙은 학생이 "무엇을 하면 되는지"를 알게 해, '
        '문제행동 예방과 규칙 준수율 향상에 효과적입니다. (SWPBS 기대행동 설정 원리)',
    ctaLabel: '규칙 설정하러 가기',
    ctaRoute: '/teacher/rules',
    color: AppColors.teacherNavy,
  ),
  _TPage(
    emoji: '💚',
    subtitle: 'STEP 2 · 매일의 긍정적 강화',
    title: '칭찬하고, 포인트로 격려해요',
    body: '학생은 매일 스스로 행동을 점검하고 포인트·배지를 모아요. '
        '선생님은 즉석 칭찬(+50P)과 명예의 전당으로 격려할 수 있어요.\n\n'
        '잘못을 지적하기보다 "잘한 행동을 알아주는 것"이 SWPBS의 핵심입니다.',
    color: AppColors.primary,
  ),
  _TPage(
    emoji: '🛡️',
    subtitle: 'STEP 3 · 지원이 필요한 학생 발견',
    title: "K-ODR은 '처벌'이 아닌 '지원'입니다",
    body: 'K-ODR은 반복되는 어려움을 조기에 발견해 학생을 돕기 위한 관찰 기록이에요. '
        '개인정보 노출을 걱정하는 목소리가 있지만, 아래를 확인하시면 안심하실 수 있어요.',
    notice: _Notice('✅',
        '이 사업은 교육감이 승인한 SWPBS 교육사업이며, 서울시교육청 행동중재전문관의 검토를 거쳤습니다. 안심하고 활용하세요.'),
    bullets: [
      '진단이 아닙니다 — 학생의 어려움을 조기에 발견해 돕기 위한 기록입니다.',
      "국가 '학생 정서·행동특성검사'를 대체하지 않는 보완 도구입니다.",
      '같은 학교 교사만 열람할 수 있고, 학생·외부에는 공개되지 않습니다.',
      '필요 시 보호자에게 안내하며, 교육 목적 외 사용은 금지됩니다.',
    ],
    warning: '⚠️ 이 기록은 다른 학교 교사에게 보여주거나 공유하지 마세요.',
    color: AppColors.teacherNavy,
  ),
];

class _TeacherOnboardingDialog extends StatefulWidget {
  const _TeacherOnboardingDialog();
  @override
  State<_TeacherOnboardingDialog> createState() => _State();
}

class _State extends State<_TeacherOnboardingDialog> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _goTo(String route) {
    // 팝 이후에도 안전하도록 라우터를 먼저 캡처.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(route);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: size.height * 0.8, maxWidth: 420),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('건너뛰기',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _PageContent(page: _pages[i], onCta: _goTo),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final selected = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected
                          ? _pages[_index].color
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pages[_index].color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSizes.radiusMd)),
                  ),
                  child: Text(_isLast ? '시작하기' : '다음',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, required this.onCta});
  final _TPage page;
  final void Function(String route) onCta;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(page.emoji, style: const TextStyle(fontSize: 46)),
          ),
          const SizedBox(height: 18),
          Text(page.subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: page.color,
                  letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Text(page.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.3)),
          const SizedBox(height: 14),
          Text(page.body,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.6)),
          if (page.researchNote != null) _box(page.researchNote!, page.color),
          if (page.notice != null) _noticeBox(page.notice!),
          if (page.bullets != null) _bullets(page.bullets!),
          if (page.warning != null) _warningBox(page.warning!),
          if (page.ctaLabel != null && page.ctaRoute != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onCta(page.ctaRoute!),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(page.ctaLabel!,
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: page.color,
                  side: BorderSide(color: page.color, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _box(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Text(text,
            style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.6)),
      );

  Widget _noticeBox(_Notice n) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.studentGreenLight,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: AppColors.studentGreen.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(n.text,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                      height: 1.6)),
            ),
          ],
        ),
      );

  Widget _bullets(List<String> items) => Container(
        margin: const EdgeInsets.only(top: 12),
        child: Column(
          children: items
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                  height: 1.55)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );

  Widget _warningBox(String text) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFDC2626),
                height: 1.5)),
      );
}
