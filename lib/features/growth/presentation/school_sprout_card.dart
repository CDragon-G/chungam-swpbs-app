import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../models/growth_status.dart';
import '../providers/growth_provider.dart';
import 'farm_widgets.dart';

/// 🌱 학교 공동 새싹 카드 — 교사·학생 홈 공용 히어로.
/// SWPBS 활동이 양분이 되어 씨앗 → 모두의 숲까지 12단계로 함께 키운다.
/// 탭하면 미션 체크리스트(튜토리얼)·활동 지표·성장 로드맵 시트.
class SchoolSproutCard extends ConsumerWidget {
  const SchoolSproutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growthAsync = ref.watch(schoolGrowthProvider);
    final g = growthAsync.value;
    if (g == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: PbsCard(
        onTap: () => showGrowthSheet(context, g),
        padding: const EdgeInsets.all(AppSizes.lg),
        color: const Color(0xFFF0FDF4),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        child: Row(
          children: [
            BreathingSprout(asset: g.levelAsset, level: g.level, size: 64),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${g.schoolName} 새싹',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.studentGreen,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Lv.${g.level} ${g.levelName}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: g.progressToNext,
                      minHeight: 8,
                      backgroundColor: Colors.white,
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.studentGreen),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    g.isMaxLevel
                        ? '🎉 숲이 되었어요! 모두가 함께 키운 결실이에요.'
                        : g.isGateLocked
                            ? '🔑 다음 단계 열쇠: ${g.gateKeyLabel}'
                            : g.isDayLocked
                                ? '🌙 양분은 가득! ${g.daysToNext}일 더 함께 자라면 ${GrowthStatus.levelNames[g.level]}이 돼요.'
                                : '다음 단계(${GrowthStatus.levelEmojis[g.level]} ${GrowthStatus.levelNames[g.level]})까지 ${g.pointsToNext}점 — 함께 키워요!',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: g.isGateLocked || g.isDayLocked
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: g.isGateLocked
                          ? const Color(0xFFB45309)
                          : g.isDayLocked
                              ? const Color(0xFF3D6B21)
                              : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// 성장 상세 시트 — 로드맵·미션 체크리스트·활동 양분.
/// 새싹 카드와 농장 홈(식물 탭)에서 공용으로 사용.
void showGrowthSheet(BuildContext context, GrowthStatus g) {
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(AppSizes.xl),
          children: [
            Center(
              child: Column(
                children: [
                  BreathingSprout(asset: g.levelAsset, level: g.level, size: 110),
                  const SizedBox(height: 6),
                  Text(
                    '${g.schoolName} 새싹',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'Lv.${g.level} ${g.levelName} · ${g.score}점 · ${g.yearLabel} ${g.days}일째',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),

            // 새 학년도 안내 — 왜 나무가 작아졌는지 먼저 말해준다
            if (g.isNewYear)
              PbsCard(
                color: const Color(0xFFFEF3C7),
                child: Text(
                  '🌱 ${g.yearLabel}가 시작됐어요.\n'
                  '새 친구들과 다시 씨앗부터 함께 키웁니다. '
                  '지난 학년도 기록은 아래에 그대로 남아 있어요.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF92400E)),
                ),
              ),
            if (g.isNewYear) const SizedBox(height: AppSizes.md),

            // 성장 로드맵
            PbsCard(
              color: const Color(0xFFF0FDF4),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 8,
                children: List.generate(GrowthStatus.levelNames.length, (i) {
                  final reached = g.level >= i + 1;
                  final here = g.level == i + 1;
                  return SizedBox(
                    width: 44,
                    child: Column(
                      children: [
                        Opacity(
                          opacity: reached ? 1 : 0.28,
                          child: Image.asset(
                            GrowthStatus.assetFor(i + 1),
                            width: here ? 38 : 26,
                            height: here ? 38 : 26,
                          ),
                        ),
                        Text(
                          'Lv.${i + 1}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 8.5,
                            fontWeight:
                                here ? FontWeight.w900 : FontWeight.w500,
                            color: reached
                                ? AppColors.studentGreen
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),

            const SectionHeader(title: '🎯 성장 미션 (각 +10점)'),
            ...g.missions.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: PbsCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.md, vertical: 10),
                    color: m.done ? const Color(0xFFF0FDF4) : null,
                    child: Row(
                      children: [
                        Icon(
                          m.done
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: m.done
                              ? AppColors.studentGreen
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            m.label,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight:
                                  m.done ? FontWeight.w700 : FontWeight.w500,
                              color: m.done
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (m.done)
                          Text('+10',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppColors.studentGreen,
                              )),
                      ],
                    ),
                  ),
                )),

            SectionHeader(title: '💧 ${g.yearLabel} 양분 (활동 점수)'),
            PbsCard(
              child: Column(
                children: [
                  _ActivityRow(
                    icon: '✅',
                    label: '최근 30일 점검 참여율',
                    value: '${g.activity.participation.toStringAsFixed(0)}%',
                    pts: g.activity.participationPts,
                    max: 40,
                  ),
                  _ActivityRow(
                    icon: '💚',
                    label: '칭찬 ${g.activity.praiseTotal}회',
                    value: '',
                    pts: g.activity.praisePts,
                    max: 25,
                  ),
                  _ActivityRow(
                    icon: '📋',
                    label: g.activity.kodrLabel,
                    value: '',
                    pts: g.activity.kodrPts,
                    max: 20,
                  ),
                  _ActivityRow(
                    icon: '🤝',
                    label: 'CICO 졸업(자립) ${g.activity.cicoGraduated}명',
                    value: '',
                    pts: g.activity.cicoPts,
                    max: 15,
                  ),
                  _ActivityRow(
                    icon: '🎁',
                    label: '교환소 강화물 ${g.activity.storeItems}개',
                    value: '',
                    pts: g.activity.storePts,
                    max: 10,
                  ),
                  _ActivityRow(
                    icon: '🛍️',
                    label: '보상 교환 수령 ${g.activity.exchanges}건',
                    value: '',
                    pts: g.activity.exchangePts,
                    max: 15,
                  ),
                  _ActivityRow(
                    icon: '🍽️',
                    label: '수업맛집 투표 참여 ${g.activity.votesCast}표',
                    value: '',
                    pts: g.activity.votePts,
                    max: 15,
                  ),
                  _ActivityRow(
                    icon: '📢',
                    label: '공지 작성 ${g.activity.announcements}건',
                    value: '',
                    pts: g.activity.announcePts,
                    max: 10,
                  ),
                  _ActivityRow(
                    icon: '🔥',
                    label: '주간 개근 보너스 ${g.activity.weeklyBonus}회',
                    value: '',
                    pts: g.activity.weeklyPts,
                    max: 10,
                  ),
                ],
              ),
            ),

            if (g.history.isNotEmpty) ...[
              const SectionHeader(title: '🏅 지난 학년도 기록'),
              PbsCard(
                child: Column(
                  children: g.history
                      .map((y) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Image.asset(GrowthStatus.assetFor(y.level),
                                    width: 34, height: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(y.year,
                                      style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),
                                Text('Lv.${y.level} ${y.name} · ${y.score}점',
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.studentGreen)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],

            const SizedBox(height: AppSizes.sm),
            Text(
              '새싹은 우리 학교 모두가 함께 키워요.\n'
              '매일 점검하고, 칭찬하고, 서로 도울수록 무럭무럭 자라요. 🌱',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textTertiary, height: 1.6),
            ),
            const SizedBox(height: AppSizes.xl),
          ],
        ),
      ),
    );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.pts,
    required this.max,
  });
  final String icon;
  final String label;
  final String value;
  final int pts;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? label : '$label $value',
              style: GoogleFonts.notoSansKr(fontSize: 12.5),
            ),
          ),
          Text(
            '+$pts / $max',
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.studentGreen,
            ),
          ),
        ],
      ),
    );
  }
}
