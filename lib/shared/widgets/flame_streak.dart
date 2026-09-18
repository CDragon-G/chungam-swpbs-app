import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 연속 참여 불꽃 단계. 불꽃 뱃지(5·10·20·50·100 수업일)와 같은 기준이다.
class FlameTier {
  const FlameTier(this.minDays, this.name, this.bottom, this.top, this.text);

  final int minDays;
  final String name;
  final Color bottom; // 불꽃 아래쪽 색
  final Color top; // 불꽃 위쪽 색
  final Color text; // 숫자 색

  static const tiers = [
    FlameTier(
        100, '전설의 불꽃', Color(0xFFFFC53D), Color(0xFF9C27B0), Color(0xFF7B1FA2)),
    FlameTier(
        50, '푸른 불꽃', Color(0xFF80DEEA), Color(0xFF1E63E9), Color(0xFF1E4FD8)),
    FlameTier(
        20, '뜨거운 불꽃', Color(0xFFFFB300), Color(0xFFD32F2F), Color(0xFFC62828)),
    FlameTier(
        10, '타오르는 불꽃', Color(0xFFFFB74D), Color(0xFFF4511E), Color(0xFFE64A19)),
    FlameTier(
        5, '작은 불꽃', Color(0xFFFFD54F), Color(0xFFFF7A18), Color(0xFFEF6C00)),
    FlameTier(1, '불씨', Color(0xFFFFE082), Color(0xFFFFA726), Color(0xFFB45309)),
  ];

  /// 연속 일수에 맞는 단계 (0 이면 null).
  static FlameTier? of(int days) {
    if (days <= 0) return null;
    return tiers.firstWhere((t) => days >= t.minDays);
  }

  /// 다음 단계까지 남은 수업일 (최고 단계면 null).
  static int? daysToNext(int days) {
    for (final t in tiers.reversed) {
      if (t.minDays > days) return t.minDays - days;
    }
    return null;
  }
}

/// 🔥 연속 참여 불꽃 — 연속이 길수록 색이 바뀐다 (주황 → 빨강 → 파랑 → 보라·금).
class FlameStreak extends StatelessWidget {
  const FlameStreak({
    super.key,
    required this.days,
    this.size = 18,
    this.label,
    this.fontSize,
  });

  final int days;
  final double size;

  /// 불꽃 옆 글자. null 이면 '$days일'.
  final String? label;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final tier = FlameTier.of(days);
    if (tier == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlameIcon(tier: tier, size: size),
        const SizedBox(width: 2),
        Text(
          label ?? '$days일',
          maxLines: 1,
          style: GoogleFonts.notoSansKr(
            fontSize: fontSize ?? size * 0.66,
            fontWeight: FontWeight.w900,
            color: tier.text,
          ),
        ),
      ],
    );
  }
}

class FlameIcon extends StatelessWidget {
  const FlameIcon({super.key, required this.tier, this.size = 18});
  final FlameTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [tier.bottom, tier.top],
      ).createShader(rect),
      child: Icon(Icons.local_fire_department_rounded, size: size),
    );
  }
}
