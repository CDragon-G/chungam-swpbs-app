import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/text_utils.dart';

/// 마지막으로 보여준 시각(ms). 일정 주기마다 다시 보여준다.
const _kLastShownKey = 'teacher_onboarding_last_ms';

/// 다시 보여주는 주기 (일). SWPBS 철학을 주기적으로 상기시키기 위함.
const _kReshowDays = 7;

/// 교사 접속 시 자람·SWPBS 활용 안내 캐로셀.
/// 처음 + 이후 7일마다 자동 표시 (건너뛰기 가능).
class TeacherOnboarding {
  TeacherOnboarding._();
  static bool _busy = false;

  static Future<void> showIfDue(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLastShownKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = now - last >= _kReshowDays * 24 * 60 * 60 * 1000;
      if (!due) return;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _TeacherOnboardingDialog(),
      );
      await prefs.setInt(_kLastShownKey, now);
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
    this.pyramid = false,
    this.flow,
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
  final bool pyramid; // Tier 1~3 피라미드 표시
  final List<(String, String)>? flow; // (이모지, 텍스트) 흐름 박스
}

const _pages = <_TPage>[
  // 1 ── SWPBS란 (연구 기반)
  _TPage(
    emoji: '🏫',
    subtitle: '학교차원 긍정적 행동지원',
    title: 'SWPBS는 검증된 시스템이에요',
    body: 'SWPBS(SWPBIS)는 처벌 대신 "기대행동을 가르치고 인정하는" '
        '학교 운영 시스템으로, 미국에서만 2만 곳이 넘는 학교가 사용하는 '
        '증거기반 실천(EBP)이에요.\n\n'
        '자람은 이 시스템을 우리나라 학교에 맞게 담은 플랫폼입니다.',
    researchNote: '📊 무작위 대조 연구에서 SWPBS 시행 학교는 훈육 의뢰와 정학이 '
        '유의미하게 감소하고 학교 분위기가 개선되었어요(Bradshaw 외, 2010). '
        '또래 괴롭힘과 따돌림도 줄어드는 것으로 나타났습니다(Waasdorp 외, 2012).',
    color: AppColors.studentGreen,
  ),
  // 2 ── 3단 피라미드
  _TPage(
    emoji: '🔺',
    subtitle: '3단계 지원 체계',
    title: 'Tier 1이 튼튼할수록\n위층이 줄어들어요',
    body: '모든 학생에게 주는 보편적 지원(Tier 1)이 잘 될수록, '
        '더 많은 도움이 필요한 학생(Tier 2·3)이 줄어듭니다.\n\n'
        '매일의 자기점검·칭찬·규칙 지도가 곧 예방 활동인 이유예요.',
    pyramid: true,
    researchNote: '💡 Tier 1이 충실히 운영되면 약 80%의 학생은 그것만으로 충분하고, '
        '나머지 학생만 표적(Tier 2)·집중(Tier 3) 지원으로 올라갑니다. '
        '토대가 약하면 위층 부담이 커져요.',
    color: AppColors.teacherNavy,
  ),
  // 3 ── 예방의 원리 (사전 신호)
  _TPage(
    emoji: '🚨',
    subtitle: '왜 예방이 가능한가',
    title: '심각한 문제행동은\n갑자기 일어나지 않아요',
    body: '학교폭력 같은 심각한 행동 이전에는 거의 언제나 '
        '작은 신호들이 먼저 나타납니다. 문제는 그 신호가 '
        '기록되지 않고 흩어져 사라진다는 것이에요.\n\n'
        '가해 학생이 된 "후"에 움직이는 게 아니라, '
        '신호가 보일 "때" 움직이는 것 — 그게 자람의 방식입니다.',
    researchNote: '📊 미국 비밀경호국·교육부의 학교 공격 사례 연구(Safe School '
        'Initiative, 2002)에서 가해 학생의 93%는 공격 전에 주변이 우려할 만한 '
        '행동 신호를 보였고, 81%는 주변의 누군가가 계획을 알고 있었어요. '
        '신호는 있었지만, 모아서 본 사람이 없었던 것입니다.',
    flow: [
      ('👀', '작은 신호 — 지각, 수업 이탈, 갈등…'),
      ('📋', 'K-ODR — 흩어진 신호를 기록으로 모아요'),
      ('🔎', '이달 3건 이상 → "지원 권장" 자동 표시'),
      ('🤝', 'CICO — 멘토와 동행하며 방향을 바꿔요'),
      ('🌱', '심각해지기 전에, 예방 완료'),
    ],
    color: AppColors.teacherNavy,
  ),
  // 4 ── STEP 1 규칙
  _TPage(
    emoji: '📋',
    subtitle: 'STEP 1 · 가장 중요한 첫걸음',
    title: '우리 학교 규칙부터 세워요',
    body: '3~4월 초, 학급자치 시간을 활용해 학생과 교사가 함께 규칙을 정하세요.\n\n'
        "규칙은 '복도에서 뛰지 않기'(✕)가 아니라 "
        "'복도에서는 걸어다녀요'(○)처럼 긍정문으로 세워야 합니다.\n\n"
        '이 규칙이 자기점검·CICO의 공통 기준이 돼요.',
    researchNote: '💡 긍정문으로 표현된 명확한 기대행동은 학생이 "무엇을 하면 되는지"를 '
        '알게 해, 문제행동 예방과 규칙 준수율 향상에 효과적입니다.',
    ctaLabel: '규칙 설정하러 가기',
    ctaRoute: '/teacher/rules',
    color: AppColors.teacherNavy,
  ),
  // 5 ── STEP 2 강화
  _TPage(
    emoji: '💚',
    subtitle: 'STEP 2 · 매일의 긍정적 강화',
    title: '칭찬하고, 포인트로 격려해요',
    body: '학생은 매일 스스로 행동을 점검하고 포인트·배지를 모아요. '
        '선생님은 즉석 칭찬(+50P)과 명예의 전당으로 격려할 수 있어요.\n\n'
        '잘못을 지적하기보다 "잘한 행동을 알아주는 것"이 SWPBS의 핵심입니다.',
    researchNote: '💡 일일 행동 자기점검은 자기조절 능력을 길러 학업 성취, 또래 관계, '
        '문제행동 감소에 효과가 있다는 연구 결과가 있어요. 칭찬과 인정은 '
        '기대행동을 유지시키는 가장 강력한 강화물입니다.',
    color: AppColors.primary,
  ),
  // 6 ── STEP 3 K-ODR 안심
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
  // 7 ── 학교 새싹 (자람의 심장)
  _TPage(
    emoji: '🌱',
    subtitle: '자람만의 방식 · 함께 키우는 성장',
    title: '우리 학교 새싹을\n다 함께 키워요',
    body: '홈 화면의 새싹은 우리 학교 SWPBS의 성장 그 자체예요. '
        '교사와 학생의 모든 긍정 활동이 양분이 되어, '
        '3월의 씨앗이 학기말엔 열매나무가 됩니다.\n\n'
        '점검·칭찬·K-ODR·CICO·수업맛집·교환소 — 무엇을 하든 새싹이 자라요.',
    flow: [
      ('🌰', '씨앗 — 규칙을 세우면 싹이 터요'),
      ('🌿', '명단·가입·첫 점검·첫 칭찬으로 쑥쑥'),
      ('🌳', '첫 K-ODR — 기록 문화가 나무를 튼튼하게'),
      ('🌸', 'CICO·수업맛집 — 꽃이 피어요'),
      ('🍎', '꾸준한 참여 — 학기말, 열매를 맺어요'),
    ],
    researchNote: '💡 K-ODR은 도입 초기엔 "작성할수록" 새싹이 자라고, '
        '문화가 자리잡은 뒤엔 "줄어들수록" 자라요 — 예방이 작동한다는 증거니까요.',
    color: AppColors.studentGreen,
  ),
  // 8 ── 수업맛집
  _TPage(
    emoji: '🍽️',
    subtitle: '교사가 함께 만드는 학급 문화',
    title: '수업맛집 — 수업 규칙을\n잘 지킨 학급에 투표해요',
    body: '매주 금요일, 우리 학교 수업 규칙을 가장 잘 실천한 학급에 '
        '투표하세요(교사 1인당 주 2표 기본).\n\n'
        '중간·기말 전 집계로 학년별 수업맛집 학급을 선정해 '
        '현판·간식 등으로 강화하면, 수업 규칙이 학교의 공용어가 됩니다.',
    flow: [
      ('🗳️', '금요일 알림 → 30초 투표'),
      ('👀', '학생도 접전 힌트를 봐요 — "1표 차 대역전!"'),
      ('🏆', '학기별 학년 1위 = 수업맛집 선정'),
    ],
    ctaLabel: '수업맛집 구경하기',
    ctaRoute: '/teacher/vote',
    color: AppColors.primary,
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
            BoxConstraints(maxHeight: size.height * 0.82, maxWidth: 420),
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
    // 좁은 화면에서는 글자를 살짝 줄여 한 문장이 자연스럽게 들어가도록
    final narrow = MediaQuery.sizeOf(context).width < 370;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(page.emoji, style: const TextStyle(fontSize: 42)),
          ),
          const SizedBox(height: 14),
          Text(page.subtitle.wordSafe,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: page.color,
                  letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Text(page.title.wordSafe,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: narrow ? 18 : 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.3)),
          const SizedBox(height: 12),
          Text(page.body.wordSafe,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: narrow ? 12.5 : 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.6)),
          if (page.pyramid) _pyramid(),
          if (page.flow != null) _flowBox(page.flow!, page.color),
          if (page.researchNote != null) _box(page.researchNote!, page.color),
          if (page.notice != null) _noticeBox(page.notice!),
          if (page.bullets != null) _bullets(page.bullets!),
          if (page.warning != null) _warningBox(page.warning!),
          if (page.ctaLabel != null && page.ctaRoute != null) ...[
            const SizedBox(height: 16),
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

  // ── Tier 1~3 피라미드 ─────────────────────────────────────
  Widget _pyramid() {
    Widget tier(String label, String pct, Color color, double widthFactor,
        {Color? textColor}) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: textColor ?? Colors.white)),
              Text(pct,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color:
                          (textColor ?? Colors.white).withValues(alpha: 0.85))),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          tier('Tier 3 · 집중 지원', '약 5%', const Color(0xFFF87171), 0.42),
          tier('Tier 2 · 표적 지원 (CICO)', '약 15%', const Color(0xFFFBBF24),
              0.68,
              textColor: const Color(0xFF7C5800)),
          tier('Tier 1 · 보편적 예방 (모든 학생)', '약 80%',
              const Color(0xFF34D399), 0.96,
              textColor: const Color(0xFF065F46)),
          const SizedBox(height: 6),
          Text('⬇️ 토대가 튼튼할수록 위층이 작아져요',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  // ── 신호→예방 흐름 박스 ───────────────────────────────────
  Widget _flowBox(List<(String, String)> steps, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(steps[i].$1, style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(steps[i].$2.wordSafe,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
              if (i != steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text('↓',
                          style: TextStyle(
                              fontSize: 11,
                              color: color.withValues(alpha: 0.6))),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );

  Widget _box(String text, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Text(text.wordSafe,
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
          border:
              Border.all(color: AppColors.studentGreen.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(n.text.wordSafe,
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
                          child: Text(t.wordSafe,
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
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(text.wordSafe,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFDC2626),
                height: 1.5)),
      );
}
