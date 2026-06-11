import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../points/providers/points_provider.dart';
import '../providers/compare_provider.dart';

class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareAsync = ref.watch(compareStatsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '비교',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(compareStatsProvider),
        child: compareAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('오류: $e')),
          data: (s) => ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              // Bar chart of 4 averages
              PbsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '평균 비교 (최근 30일)',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),
                    _BarLine(label: '나', value: s.myAvg, color: AppColors.primary),
                    _BarLine(label: '우리 반', value: s.classAvg, color: AppColors.studentGreen),
                    _BarLine(label: '학년', value: s.gradeAvg, color: AppColors.colorR),
                    _BarLine(label: '전교생', value: s.schoolAvg, color: AppColors.teacherNavy),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              PbsCard(
                color: AppColors.primaryLight,
                child: Column(
                  children: [
                    Text(
                      '🏆 전교 상위 ${s.percentile}%',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      s.myRank > 0
                          ? '전교 ${s.myRank}위'
                          : '아직 데이터가 충분하지 않아요',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: '🏅 우리 반 익명 순위'),
              PbsCard(
                child: s.anonymousRanking.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          '아직 같은 반 친구들의 데이터가 없어요.',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0;
                              i < s.anonymousRanking.length && i < 20;
                              i++)
                            _RankRow(
                              rank: i + 1,
                              item: s.anonymousRanking[i],
                            ),
                        ],
                      ),
              ),
              const SectionHeader(title: '🏫 전국 학교 점수 랭킹'),
              const _SchoolLeaderboard(),
              const SizedBox(height: AppSizes.xxxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (value / 100).clamp(0, 1).toDouble(),
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '${value.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.item});
  final int rank;
  final ({String label, double score, bool isMe}) item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: item.isMe ? FontWeight.w900 : FontWeight.w500,
                color: item.isMe ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${item.score.toStringAsFixed(1)}%',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.scoreColor(item.score),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchoolLeaderboard extends ConsumerWidget {
  const _SchoolLeaderboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(schoolLeaderboardProvider);
    final myEntry = ref.watch(mySchoolEntryProvider);
    final profile = ref.watch(profileProvider).value;

    return Column(
      children: [
        // Explanation
        PbsCard(
          color: AppColors.primaryLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    '학교 점수 = 참여율 × 평균점수 × 10',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '학생 수가 적은 학교도 모두가 참여하면 1등 가능!',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),

        // My school card
        myEntry.when(
          loading: () => const PbsCard(
            child: SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (entry) {
            if (entry == null) return const SizedBox.shrink();
            return PbsCard(
              color: AppColors.primary,
              border: Border.all(color: AppColors.primary),
              child: Row(
                children: [
                  const Text('🏫', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '우리 학교 점수',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          '${NumberFormat('#,###').format(entry.schoolScore)}점',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '참여 ${entry.participants30d}명 / 평균 ${entry.avgScore30d.toStringAsFixed(1)}점',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSizes.md),

        // Ranking list
        leaderboard.when(
          loading: () => const PbsCard(
            child: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => PbsCard(child: Text('오류: $e')),
          data: (list) {
            if (list.isEmpty) {
              return PbsCard(
                child: Text(
                  '아직 참여 중인 학교가 없어요.',
                  style: GoogleFonts.notoSansKr(
                    color: AppColors.textTertiary,
                  ),
                ),
              );
            }
            final myId = profile?.schoolId;
            return PbsCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length && i < 30; i++)
                    _LeaderRow(rank: i + 1, entry: list[i], isMine: list[i].id == myId),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.entry, required this.isMine});
  final int rank;
  final dynamic entry;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    String medal() => switch (rank) {
          1 => '🥇',
          2 => '🥈',
          3 => '🥉',
          _ => '$rank',
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primaryLight : null,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              medal(),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: rank <= 3 ? 18 : 13,
                fontWeight: FontWeight.w800,
                color: isMine ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: isMine ? FontWeight.w900 : FontWeight.w700,
                          color: isMine ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.star_rounded, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                Text(
                  '${entry.region} · ${entry.level} · ${entry.studentCount}명',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${NumberFormat('#,###').format(entry.schoolScore)}',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
