import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/text_utils.dart';

const _kOnboardingDoneKey = 'onboarding_done_v1';

class OnboardingDialog {
  OnboardingDialog._();

  /// Show the onboarding carousel if user hasn't seen it before.
  static Future<void> showIfFirstLaunch(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kOnboardingDoneKey) == true) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OnboardingDialog(),
    );
    await prefs.setBool(_kOnboardingDoneKey, true);
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.color,
    this.researchNote,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String body;
  final Color color;
  final String? researchNote;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    emoji: '🌱',
    title: '매일 1분, 행동을 점검해요',
    subtitle: 'SWPBS 학교 차원 긍정적 행동지원',
    body:
        '수업·교실·복도·급식실·화장실에서 우리 학교의 약속을 잘 지켰는지 매일 스스로 점검합니다.',
    researchNote:
        '💡 일일 행동 자기점검은 자기조절 능력을 길러 학업 성취도 향상, 또래 관계 개선, 학교폭력·문제행동 감소에 효과가 있다는 연구 결과가 있어요.',
    color: AppColors.studentGreen,
  ),
  _OnboardingPage(
    emoji: '🪙',
    title: '포인트 모으고 교환해요',
    subtitle: '강화물 교환 시스템',
    body:
        '점검 한 번 = 100P, 월~금 모두 참여 시 +500P 보너스! 모은 포인트로 인성생활부에서 정한 간식·음료 등으로 교환할 수 있어요.',
    color: AppColors.primary,
  ),
  _OnboardingPage(
    emoji: '🏆',
    title: '함께 자라는 우리 학교',
    subtitle: '비교 + 학교 경쟁',
    body:
        '나·우리 반·학년·전교생 평균을 비교하고, 전국 자람 사용 학교들과 학교 점수로 경쟁! 모두가 참여할수록 우리 학교 점수가 올라가요.',
    color: AppColors.teacherNavy,
  ),
  _OnboardingPage(
    emoji: '🌳',
    title: '우리 학교 새싹을 키워요',
    subtitle: '자람만의 공동 성장',
    body: '홈 화면의 새싹은 우리 학교 모두의 것! 내가 점검하고, 칭찬받고, '
        '보상을 교환할 때마다 새싹이 자라요. 선생님들과 힘을 모아 '
        '씨앗 🌰에서 열매나무 🍎까지 키워보세요!',
    researchNote:
        '💡 나의 긍정적 행동 하나하나가 학교 전체의 성장이 되는 것 — 그게 자람(성장)이라는 이름의 의미예요.',
    color: AppColors.studentGreen,
  ),
];

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
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

  void _skip() => Navigator.of(context).pop();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: size.height * 0.75,
          maxWidth: 400,
        ),
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  '건너뛰기',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _PageContent(page: _pages[i]),
              ),
            ),

            // Dot indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
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

            // Next / Start button
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
                          BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                  child: Text(
                    _isLast ? '시작하기' : '다음',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
  const _PageContent({required this.page});
  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Big emoji circle
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(page.emoji, style: const TextStyle(fontSize: 52)),
          ),
          const SizedBox(height: 20),
          Text(
            page.subtitle.wordSafe,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: page.color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            page.title.wordSafe,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body.wordSafe,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (page.researchNote != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: page.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(
                page.researchNote!.wordSafe,
                textAlign: TextAlign.start,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
