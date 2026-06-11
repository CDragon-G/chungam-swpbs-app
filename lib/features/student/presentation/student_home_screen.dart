import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/models/badge.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/score_ring_chart.dart';
import '../../../shared/widgets/streak_badge_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../checkin/models/daily_checkin.dart';
import '../../checkin/providers/checkin_provider.dart';
import '../../school/providers/school_provider.dart';
import '../providers/badge_provider.dart';
import '../providers/student_stats_provider.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final stats = ref.watch(studentStatsProvider);
    final today = ref.watch(todayCheckinProvider);
    final announcements = ref.watch(announcementsProvider);
    final allBadges = ref.watch(allBadgesProvider);
    final myBadges = ref.watch(userBadgesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(studentStatsProvider);
        ref.invalidate(todayCheckinProvider);
        ref.invalidate(announcementsProvider);
        ref.invalidate(userBadgesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.lg,
          AppSizes.lg,
          AppSizes.xxxl,
        ),
        children: [
          // Greeting row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '안녕하세요, ${profile?.nickname ?? ''}! 🌟',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      KstDate.formatKorean(KstDate.today()),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '로그아웃',
                icon: const Icon(Icons.logout_rounded, size: 20),
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/welcome');
                },
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Align(
            alignment: Alignment.centerLeft,
            child: StreakBadge(days: stats.value?.streak ?? 0),
          ),
          const SizedBox(height: AppSizes.lg),

          // Today's status card
          _TodayStatusCard(
            todayAsync: today,
            onCheckIn: () => context.go('/student/checkin'),
          ),

          // Announcements
          announcements.when(
            data: (anns) {
              if (anns.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  const SectionHeader(title: '📢 공지'),
                  PbsCard(
                    color: AppColors.primaryLight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: anns.take(2).map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a['title'] as String,
                                  style: GoogleFonts.notoSansKr(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  a['body'] as String,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Weekly snapshot
          const SectionHeader(title: '최근 7일'),
          PbsCard(
            child: SizedBox(
              height: 160,
              child: _WeeklyBars(stats: stats),
            ),
          ),

          // Recent badges
          allBadges.when(
            data: (defs) {
              final earned = myBadges.value ?? const <UserBadge>[];
              if (earned.isEmpty) return const SizedBox.shrink();
              final recent = ([...earned]..sort(
                  (a, b) => b.earnedAt.compareTo(a.earnedAt))).take(3).toList();
              return Column(
                children: [
                  SectionHeader(
                    title: '🏆 최근 획득 뱃지',
                    action: TextButton(
                      onPressed: () => context.go('/student/badges'),
                      child: Text(
                        '전체 보기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  PbsCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: recent.map((ub) {
                        final def = defs.firstWhere(
                          (b) => b.id == ub.badgeId,
                          orElse: () => BadgeDef(
                            id: '',
                            name: '?',
                            description: '',
                            iconEmoji: '🎖️',
                            conditionType: '',
                            conditionValue: 0,
                          ),
                        );
                        return Column(
                          children: [
                            Text(def.iconEmoji,
                                style: const TextStyle(fontSize: 32)),
                            const SizedBox(height: 4),
                            Text(
                              def.name,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({required this.todayAsync, required this.onCheckIn});
  final AsyncValue<DailyCheckin?> todayAsync;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    return todayAsync.when(
      loading: () => const PbsCard(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => PbsCard(
        child: Text('오류: $e',
            style: GoogleFonts.notoSansKr(color: AppColors.danger)),
      ),
      data: (today) {
        if (today == null) {
          return PbsCard(
            color: AppColors.primaryLight,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            child: Column(
              children: [
                const Text('📋', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                Text(
                  '오늘 자기점검을 아직 하지 않았어요',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '1분이면 충분해요 😊',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                PbsPrimaryButton(
                  label: '오늘 점검하기',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.studentGreen,
                  onPressed: onCheckIn,
                ),
              ],
            ),
          );
        }
        return PbsCard(
          child: Row(
            children: [
              ScoreRingChart(scorePct: today.scorePct, size: 110, strokeWidth: 12),
              const SizedBox(width: AppSizes.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘 ${today.scorePct.round()}% 달성!',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...today.categoryScores.entries.take(4).map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.categoryColor(e.key),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                '${e.value.round()}%',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.stats});
  final AsyncValue<StudentStats> stats;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (s) {
        final today = KstDate.today();
        final byDate = {
          for (final c in s.last30) KstDate.formatYmd(c.checkinDate): c.scorePct,
        };
        final bars = <BarChartGroupData>[];
        final labels = <String>[];
        for (var i = 6; i >= 0; i--) {
          final d = today.subtract(Duration(days: i));
          final score = byDate[KstDate.formatYmd(d)] ?? 0.0;
          bars.add(BarChartGroupData(
            x: 6 - i,
            barRods: [
              BarChartRodData(
                toY: score,
                width: 18,
                borderRadius: BorderRadius.circular(6),
                color: score == 0
                    ? AppColors.borderLight
                    : AppColors.scoreColor(score),
              ),
            ],
          ));
          labels.add(KstDate.formatShort(d));
        }
        return BarChart(
          BarChartData(
            maxY: 100,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            barGroups: bars,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[v.toInt()],
                      style: GoogleFonts.notoSansKr(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
