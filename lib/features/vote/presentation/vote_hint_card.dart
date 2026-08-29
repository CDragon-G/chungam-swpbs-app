import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../providers/vote_provider.dart';

/// 🍽️ 수업맛집 진행 현황 + 재미 힌트 카드.
/// 교사·학생 화면 공용 — 순위·학급명은 감추고 접전 상황만 보여준다.
/// 진행 중인 투표가 없으면 아무것도 그리지 않는다.
class VoteHintCard extends ConsumerWidget {
  const VoteHintCard({super.key, this.compact = false});

  /// 학생 홈 등 좁은 자리에 넣을 때 여백 축소.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hintAsync = ref.watch(voteHintProvider);
    final hint = hintAsync.value;
    if (hint == null || !hint.hasRound) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? AppSizes.sm : AppSizes.md),
      child: PbsCard(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFECDD3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🍽️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '수업맛집 투표 진행 중!',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: const Color(0xFFBE123C),
                    ),
                  ),
                ),
                // 학년마다 시험 일정이 달라 주차가 따로 흐른다.
                // 학년이 하나뿐이거나 모두 같은 주차일 때만 한 줄로 보여준다.
                if (hint.grades.map((g) => g.weekNow).toSet().length <= 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFBE123C).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${hint.weekNow}/${hint.totalWeeks}주차',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFBE123C),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hint.title,
              style: GoogleFonts.notoSansKr(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (hint.grades.isEmpty)
              Text(
                '아직 첫 표를 기다리는 중이에요. 수업 규칙을 잘 지키면 우리 반이 수업맛집! 🌱',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5, height: 1.5),
              )
            else
              ...hint.grades.map((g) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${g.grade}학년',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: g.isPaused || g.closed
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // 학년별 주차 — 3학년이 시험으로 쉬면 여기서 멈춰 보인다
                        SizedBox(
                          width: 44,
                          child: Text(
                            g.closed ? '마감' : '${g.weekNow}/${g.totalWeeks}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            g.message,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 12.5,
                                height: 1.45,
                                color: g.isPaused || g.closed
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
