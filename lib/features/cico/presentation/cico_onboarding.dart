import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

const _kCicoOnboardingKey = 'cico_onboarding_done_v1';

/// CICO 사용법 캐로셀 — 첫 진입 시 자동, ❓ 버튼으로 언제든 다시 보기.
class CicoOnboarding {
  CicoOnboarding._();
  static bool _busy = false;

  static Future<void> showIfFirstLaunch(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kCicoOnboardingKey) == true) return;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CicoOnboardingDialog(),
      );
      await prefs.setBool(_kCicoOnboardingKey, true);
    } finally {
      _busy = false;
    }
  }

  static Future<void> showAlways(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _CicoOnboardingDialog(),
      );
}

class _CPage {
  const _CPage({
    required this.emoji,
    required this.subtitle,
    required this.title,
    required this.body,
    required this.color,
    this.steps,
    this.tip,
  });

  final String emoji;
  final String subtitle;
  final String title;
  final String body;
  final Color color;
  final List<(String, String)>? steps; // (이모지, 텍스트)
  final String? tip;
}

const _pages = <_CPage>[
  _CPage(
    emoji: '🤝',
    subtitle: 'CICO 동행 점검이란?',
    title: '혼자가 아니라, 함께 자라요',
    body: '조금 더 관심이 필요한 학생과 멘토 선생님이 '
        '매일 아침·하교에 만나 함께 점검하는 Tier 2 지원이에요.\n\n'
        '처벌이 아니라 격려가 목적! 목표를 꾸준히 달성하면 졸업해요.',
    steps: [
      ('🌱', '학생 등록 — 목표·멘토 정하기'),
      ('☀️', '아침 체크인 — 오늘 목표 세우기'),
      ('🌙', '하교 체크아웃 — 함께 점수 매기기'),
      ('🏠', '가정 — 소감 쓰고 보호자 서명'),
      ('🎓', '목표 달성이 쌓이면 졸업!'),
    ],
    color: AppColors.teacherNavy,
  ),
  _CPage(
    emoji: '🌱',
    subtitle: 'STEP 1 · 학생 등록',
    title: '함께할 학생을 등록해요',
    body: 'K-ODR에 이달 3건 이상 기록된 학생은 "지원 권장"으로 표시돼요. '
        '그 화면에서 [CICO 시작하기]를 누르거나, '
        '여기 [학생 등록] 버튼으로 직접 등록할 수 있어요.',
    steps: [
      ('🎯', '목표 달성률 — 기본 80% (조정 가능)'),
      ('👩‍🏫', '멘토 — 매일 만날 선생님 (기본: 나)'),
      ('📝', '시작 사유 — 기록으로 남겨요'),
    ],
    tip: '💡 처음엔 목표를 조금 낮게(70%) 잡아 성공 경험부터 만들어주는 것도 좋아요.',
    color: AppColors.studentGreen,
  ),
  _CPage(
    emoji: '☀️',
    subtitle: 'STEP 2 · 아침 체크인 (2~3분)',
    title: '하루를 목표로 시작해요',
    body: '등교하면 멘토와 잠깐 만나요.\n\n'
        '어제 달성률을 함께 보며 축하하고, '
        '오늘의 목표를 한 줄로 정해 입력해요.',
    steps: [
      ('👀', '어제 달성률 확인 — "어제 목표 넘었네!"'),
      ('✏️', '오늘 목표 입력 — "수업 시간에 3번 발표하기"'),
    ],
    color: AppColors.warning,
  ),
  _CPage(
    emoji: '🌙',
    subtitle: 'STEP 3 · 하교 체크아웃 (5분)',
    title: '나란히 앉아 함께 점검해요',
    body: '선생님 폰 화면을 함께 보며, 항목을 하나씩 읽어주세요. '
        '학생이 스스로 0·1·2로 답하면 선생님이 입력해요.\n\n'
        '스스로 평가하는 과정 자체가 자기조절력을 길러줘요.',
    steps: [
      ('🗣️', '"복도에서는 걸어다녔나요?"'),
      ('🙋', '학생: "2점이요!"'),
      ('👆', '교사가 입력 → 달성률이 실시간으로'),
      ('💬', '격려 한마디 쓰고 저장'),
    ],
    tip: '💡 점수가 서로 다르면 논쟁하지 말고 학생 쪽으로 살짝 후하게 — '
        '목적은 채점이 아니라 관계와 자기인식이에요.',
    color: AppColors.teacherNavy,
  ),
  _CPage(
    emoji: '🏠',
    subtitle: 'STEP 4 · 가정 연계 & 졸업',
    title: '가정과 함께, 그리고 졸업까지',
    body: '집에서 학생이 자기 폰으로 오늘의 소감을 쓰고, '
        '보호자가 화면에 손가락으로 서명해요.\n\n'
        '목표 달성이 꾸준히 쌓이면 ⋮ 메뉴에서 졸업 처리! '
        '낙인이 아니라 "잠깐 더 관심받고 다시 잘 지내는" 과정이에요.',
    steps: [
      ('✍️', '학생 — 오늘의 소감 쓰기'),
      ('👨‍👩‍👧', '보호자 — 앱에서 바로 서명'),
      ('🎓', '꾸준한 달성 → 졸업 → Tier 1 복귀'),
    ],
    color: AppColors.studentGreen,
  ),
];

class _CicoOnboardingDialog extends StatefulWidget {
  const _CicoOnboardingDialog();
  @override
  State<_CicoOnboardingDialog> createState() => _State();
}

class _State extends State<_CicoOnboardingDialog> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
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
          borderRadius: BorderRadius.circular(AppSizes.radiusLg)),
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
                itemBuilder: (context, i) => _PageContent(page: _pages[i]),
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
  const _PageContent({required this.page});
  final _CPage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(page.emoji, style: const TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 16),
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
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.3)),
          const SizedBox(height: 12),
          Text(page.body,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.6)),
          if (page.steps != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: page.color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Column(
                children: page.steps!
                    .map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$1,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(s.$2,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                        color: AppColors.textPrimary)),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (page.tip != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.studentGreenLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(page.tip!,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                      height: 1.55)),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
