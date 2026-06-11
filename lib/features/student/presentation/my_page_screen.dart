import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/category_radar_chart.dart';
import '../../../shared/widgets/participation_heatmap.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../points/providers/points_provider.dart';
import '../providers/student_stats_provider.dart';

class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final statsAsync = ref.watch(studentStatsProvider);
    final pointsAsync = ref.watch(myPointsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(studentStatsProvider);
        ref.invalidate(myPointsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl,
        ),
        children: [
          // Profile card
          PbsCard(
            color: AppColors.studentGreenLight,
            border: Border.all(color: AppColors.studentGreen.withValues(alpha: 0.2)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.studentGreen,
                  child: Text(
                    (profile?.nickname.characters.first ?? '?'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.nickname ?? '',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        profile?.classLabel ?? '',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                statsAsync.maybeWhen(
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('🔥 ${s.streak}일',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800)),
                      Text('총 ${s.totalCount}회',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Points card
          const SectionHeader(title: '🪙 내 포인트'),
          PbsCard(
            color: AppColors.studentGreen,
            border: Border.all(color: AppColors.studentGreen),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 36)),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '보유 포인트',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        '${NumberFormat('#,###').format(pointsAsync.value ?? 0)} P',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.go('/student/store'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.studentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_bag_rounded, size: 16),
                  label: Text(
                    '상점',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick links row
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _QuickLinkCard(
                  icon: Icons.emoji_events_rounded,
                  label: '뱃지 갤러리',
                  color: AppColors.primary,
                  onTap: () => context.go('/student/badges'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _QuickLinkCard(
                  icon: Icons.receipt_long_rounded,
                  label: '포인트 내역',
                  color: AppColors.studentGreen,
                  onTap: () => context.go('/student/points-history'),
                ),
              ),
            ],
          ),

          const SectionHeader(title: '📈 최근 30일 점수 추이'),
          PbsCard(child: SizedBox(height: 200, child: _ScoreTrend(stats: statsAsync))),

          const SectionHeader(title: '🎯 카테고리 평균'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 200,
                child: Center(child: Text('오류: $e')),
              ),
              data: (s) => CategoryRadarChart(scores: s.categoryAverages),
            ),
          ),

          const SectionHeader(title: '🗓️ 참여 캘린더'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('오류: $e'),
              data: (s) {
                final byDate = <String, double>{
                  for (final c in s.last30)
                    KstDate.formatYmd(c.checkinDate): c.scorePct,
                };
                return ParticipationHeatmap(scoresByDate: byDate, weeks: 8);
              },
            ),
          ),

          const SectionHeader(title: '🧭 분석'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('오류: $e'),
              data: (s) {
                final delta = s.weekDelta;
                final deltaText = delta.abs() < 0.5
                    ? '지난주와 비슷한 수준이에요.'
                    : delta > 0
                        ? '지난주보다 ${delta.toStringAsFixed(1)}% 향상됐어요! 🎉'
                        : '지난주보다 ${(-delta).toStringAsFixed(1)}% 낮아요. 다시 도전!';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnalysisLine(
                      icon: '💪',
                      label: '가장 잘 지킨 규칙',
                      value: s.bestRuleText ?? '아직 데이터 부족',
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '🌱',
                      label: '더 신경 써야 할 규칙',
                      value: s.worstRuleText ?? '아직 데이터 부족',
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '📊',
                      label: '주간 변화',
                      value: deltaText,
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '🏅',
                      label: '최장 연속 기록',
                      value: '${s.longestStreak}일',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisLine extends StatelessWidget {
  const _AnalysisLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreTrend extends StatelessWidget {
  const _ScoreTrend({required this.stats});
  final AsyncValue<StudentStats> stats;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (s) {
        if (s.last30.isEmpty) {
          return Center(
            child: Text(
              '아직 점검 기록이 없어요.',
              style: GoogleFonts.notoSansKr(color: AppColors.textTertiary),
            ),
          );
        }
        final sorted = [...s.last30]
          ..sort((a, b) => a.checkinDate.compareTo(b.checkinDate));
        final spots = <FlSpot>[
          for (var i = 0; i < sorted.length; i++)
            FlSpot(i.toDouble(), sorted[i].scorePct),
        ];
        return LineChart(
          LineChartData(
            minY: 0,
            maxY: 100,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 25,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.primary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PbsCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
