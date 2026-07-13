import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../models/growth_status.dart';

/// ── 올팜식 농장 홈 공용 위젯 ─────────────────────────────────
/// 풀스크린 농장 배경 위에 얹는 부품들: 숨쉬는 식물, 학교 팻말,
/// 좌/우 플로팅 메뉴 버튼, 성장 진행바.

/// 숨쉬듯 살랑이는 식물 일러스트 — 부유 + 기울임 + 레벨업 팝.
class BreathingSprout extends StatefulWidget {
  const BreathingSprout({
    super.key,
    required this.asset,
    required this.level,
    this.size = 64,
  });
  final String asset;
  final int level;
  final double size;

  @override
  State<BreathingSprout> createState() => _BreathingSproutState();
}

class _BreathingSproutState extends State<BreathingSprout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.elasticOut,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: AnimatedBuilder(
        key: ValueKey('${widget.level}-${widget.asset}'),
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(0, -3.0 * t),
            child: Transform.rotate(
              angle: (t - 0.5) * 0.05,
              child: Transform.scale(scale: 1.0 + 0.04 * t, child: child),
            ),
          );
        },
        child: Image.asset(
          widget.asset,
          width: widget.size,
          height: widget.size,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// 나무 팻말 + 학교 이름 + 레벨 배지 (상단 중앙).
class SchoolSign extends StatelessWidget {
  const SchoolSign({
    super.key,
    required this.name,
    this.levelLabel,
    this.onTap,
  });
  final String name;
  final String? levelLabel; // 예: 'Lv.5 튼튼한 나무'
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 236,
        height: 108,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/farm/prop_sign.png',
              width: 236,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 팻말 널빤지 중앙에 오도록 살짝 위 배치
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      name,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF5B3A1E),
                        shadows: const [
                          Shadow(
                              color: Color(0x55FFFFFF), offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (levelLabel != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xCC5B8C2A),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      levelLabel!,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 좌/우 플로팅 메뉴 버튼 — 흰 원형 아이콘 + 라벨 필 (올팜 스타일).
class FarmMenuButton extends StatelessWidget {
  const FarmMenuButton({
    super.key,
    required this.asset,
    required this.label,
    required this.onTap,
    this.badge,
  });
  final String asset;
  final String label;
  final VoidCallback onTap;
  final String? badge; // 예: '!' 또는 'N'

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset(asset,
                      filterQuality: FilterQuality.medium),
                ),
                if (badge != null)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 식물 아래 성장 진행바 — "레벨업까지 n점!" (관문이면 🔑 안내).
class GrowthProgressBar extends StatelessWidget {
  const GrowthProgressBar({super.key, required this.growth});
  final GrowthStatus growth;

  @override
  Widget build(BuildContext context) {
    final g = growth;
    final label = g.isMaxLevel
        ? '🎉 열매를 맺었어요!'
        : g.isGateLocked
            ? '🔑 ${g.gateKeyLabel}'
            : '레벨업까지 ${g.pointsToNext}점!';
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: g.progressToNext,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.studentGreen),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.notoSansKr(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: g.isGateLocked
                    ? const Color(0xFFB45309)
                    : AppColors.studentGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 하단 공지 배너 — 반투명 흰 바.
class FarmNoticeBanner extends StatelessWidget {
  const FarmNoticeBanner({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('📢', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
