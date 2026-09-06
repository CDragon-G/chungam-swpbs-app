import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../models/growth_status.dart';

/// 화면 크기 기반 농장 홈 스케일 (기준 390x780, 작은/확대 화면에서 축소).
double farmScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final s = math.min(size.width / 390.0, size.height / 780.0);
  return s.clamp(0.62, 1.0);
}

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
    this.scale = 1,
  });
  final String name;
  final String? levelLabel; // 예: 'Lv.5 튼튼한 나무'
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 236 * scale,
        height: 108 * scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/farm/prop_sign.png',
              width: 236 * scale,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            // 판자 면(이미지의 세로 8~74% 구간) 중앙에 오도록 위로 보정
            Align(
              alignment: const Alignment(0, -0.25),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 36 * scale),
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
            ),
            if (levelLabel != null)
              Align(
                alignment: const Alignment(0, 0.18),
                child: Container(
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
    this.scale = 1,
  });
  final String asset;
  final String label;
  final VoidCallback onTap;
  final String? badge; // 예: '!' 또는 'N'
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46 * scale,
                  height: 46 * scale,
                  padding: EdgeInsets.all(5 * scale),
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
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 9.5 * scale,
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

/// 식물 아래 성장 진행바 — 레벨 이름 + 진행률(%)을 명확하게.
/// 관문에 걸렸으면 🔑 안내는 아래 별도 칩으로 분리 (올팜식 레이아웃).
class GrowthProgressBar extends StatelessWidget {
  const GrowthProgressBar({super.key, required this.growth, this.scale = 1});
  final GrowthStatus growth;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final g = growth;
    final pct = (g.progressToNext * 100).round();
    final sc = scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 236 * sc,
          padding: EdgeInsets.fromLTRB(14 * sc, 9 * sc, 14 * sc, 10 * sc),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
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
              Row(
                children: [
                  Text(
                    'Lv.${g.level} ${g.levelName}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13 * sc,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF3D6B21),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    g.isMaxLevel
                        ? 'MAX'
                        : g.isGateLocked
                            ? '양분 가득!'
                            : '$pct%',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13 * sc,
                      fontWeight: FontWeight.w900,
                      color: AppColors.studentGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: g.progressToNext,
                  minHeight: 12 * sc,
                  backgroundColor: const Color(0xFFE9E5D8),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.studentGreen),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                g.isMaxLevel
                    ? '🎉 숲이 되었어요! 모두의 결실이에요'
                    : g.isGateLocked
                        ? '🔑 열쇠 미션만 끝나면 바로 레벨업!'
                        : g.isDayLocked
                            ? '🌙 ${g.daysToNext}일 더 함께 자라면 레벨업!'
                            : '레벨업까지 ${100 - pct}% 남았어요!',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11 * sc,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // 관문 열쇠 — 별도 칩 (진행바 박스와 분리해 어색함 제거)
        if (g.isGateLocked)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFF5D08C)),
            ),
            child: Text(
              '🔑 다음 열쇠: ${g.gateKeyLabel}',
              style: GoogleFonts.notoSansKr(
                fontSize: 11 * sc,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF9A6A0B),
              ),
            ),
          ),
      ],
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
                textAlign: TextAlign.center,
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

/// 🌱 식물 말풍선 — 식물이 말을 건네는 연출.
/// [pinned]가 있으면 항상 그 메시지(예: 관문 잠김 안내)를 보여주고,
/// 없으면 [messages] 중 하나를 랜덤으로 골라 주기적으로 바꿔가며 응원한다.
class PlantSpeechBubble extends StatefulWidget {
  const PlantSpeechBubble({
    super.key,
    this.pinned,
    this.messages = const [],
    this.scale = 1,
  });
  final String? pinned;
  final List<String> messages;
  final double scale;

  @override
  State<PlantSpeechBubble> createState() => _PlantSpeechBubbleState();
}

class _PlantSpeechBubbleState extends State<PlantSpeechBubble> {
  final _rand = math.Random();
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.messages.isNotEmpty) {
      _idx = _rand.nextInt(widget.messages.length);
    }
    // 고정 메시지가 없을 때만 9초마다 다른 응원 멘트로 교체
    if (widget.pinned == null && widget.messages.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 9), (_) {
        if (!mounted) return;
        setState(() {
          _idx = (_idx + 1 + _rand.nextInt(widget.messages.length - 1)) %
              widget.messages.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPinned = widget.pinned != null;
    final text = widget.pinned ??
        (widget.messages.isEmpty ? '' : widget.messages[_idx]);
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Container(
            key: ValueKey(text),
            constraints: BoxConstraints(maxWidth: 252 * widget.scale),
            padding: EdgeInsets.symmetric(
                horizontal: 13 * widget.scale, vertical: 8 * widget.scale),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: isPinned
                  ? Border.all(color: const Color(0xFFF5D08C), width: 1.4)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 11.5 * widget.scale,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: isPinned
                    ? const Color(0xFF9A6A0B)
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        // 말풍선 꼬리 (식물 쪽으로)
        Transform.translate(
          offset: const Offset(0, -5),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                border: isPinned
                    ? const Border(
                        right: BorderSide(
                            color: Color(0xFFF5D08C), width: 1.4),
                        bottom: BorderSide(
                            color: Color(0xFFF5D08C), width: 1.4),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
