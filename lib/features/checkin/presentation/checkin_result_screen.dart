import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/score_ring_chart.dart';
import '../../points/models/point_transaction.dart';
import '../../points/providers/points_provider.dart';
import '../providers/checkin_provider.dart';

class CheckinResultScreen extends ConsumerWidget {
  const CheckinResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayCheckinProvider);
    final historyAsync = ref.watch(myPointsHistoryProvider);
    final balanceAsync = ref.watch(myPointsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/student/home'),
        ),
      ),
      body: todayAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (c) {
          if (c == null) {
            return Center(
              child: Text(
                '저장된 점검 결과를 찾을 수 없어요.',
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary),
              ),
            );
          }

          // Today's earned points (from history)
          final today = KstDate.today();
          final todayStr = KstDate.formatYmd(today);
          final List<PointTransaction> earnedToday =
              historyAsync.maybeWhen<List<PointTransaction>>(
            data: (txs) => txs
                .where((t) =>
                    t.isEarn &&
                    (t.reason == 'checkin_daily' ||
                        t.reason == 'checkin_weekly') &&
                    KstDate.formatYmd(t.createdAt) == todayStr)
                .toList(),
            orElse: () => const <PointTransaction>[],
          );
          final totalEarnedToday = earnedToday.fold<int>(
            0,
            (sum, t) => sum + t.amount,
          );
          final hasWeeklyBonus =
              earnedToday.any((t) => t.reason == 'checkin_weekly');

          return ListView(
            padding: const EdgeInsets.all(AppSizes.xl),
            children: [
              const SizedBox(height: AppSizes.md),

              // 🎉 Points earned banner
              if (totalEarnedToday > 0)
                _PointsEarnedBanner(
                  earned: totalEarnedToday,
                  hasWeeklyBonus: hasWeeklyBonus,
                  totalBalance: balanceAsync.value ?? 0,
                  onTapStore: () => context.go('/student/store'),
                ),
              if (totalEarnedToday > 0) const SizedBox(height: AppSizes.lg),

              Center(
                child: ScoreRingChart(
                  scorePct: c.scorePct,
                  size: 200,
                  strokeWidth: 20,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              Text(
                c.scorePct >= 80
                    ? '훌륭해요! 🌟'
                    : c.scorePct >= 60
                        ? '잘 했어요 💪'
                        : '내일은 더 잘할 수 있어요 🌱',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              Center(
                child: Text(
                  '오늘 ${c.totalScore} / ${c.totalPossible} 항목을 잘 지켰어요',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              const SectionHeader(title: '카테고리별 점수'),
              PbsCard(
                child: Column(
                  children: c.categoryScores.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              e.key,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: e.value / 100,
                                minHeight: 10,
                                backgroundColor: AppColors.borderLight,
                                valueColor: AlwaysStoppedAnimation(
                                  AppColors.scoreColor(e.value),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${e.value.round()}%',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),

              // CTA row: 상점 / 홈
              if (totalEarnedToday > 0)
                Row(
                  children: [
                    Expanded(
                      child: PbsSecondaryButton(
                        label: '홈으로',
                        color: AppColors.studentGreen,
                        onPressed: () => context.go('/student/home'),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      flex: 2,
                      child: PbsPrimaryButton(
                        label: '🛒 교환소에서 사용',
                        color: AppColors.studentGreen,
                        onPressed: () => context.go('/student/store'),
                      ),
                    ),
                  ],
                )
              else
                PbsPrimaryButton(
                  label: '홈으로 돌아가기',
                  color: AppColors.studentGreen,
                  onPressed: () => context.go('/student/home'),
                ),
              const SizedBox(height: AppSizes.md),
            ],
          );
        },
      ),
    );
  }
}

class _PointsEarnedBanner extends StatefulWidget {
  const _PointsEarnedBanner({
    required this.earned,
    required this.hasWeeklyBonus,
    required this.totalBalance,
    required this.onTapStore,
  });

  final int earned;
  final bool hasWeeklyBonus;
  final int totalBalance;
  final VoidCallback onTapStore;

  @override
  State<_PointsEarnedBanner> createState() => _PointsEarnedBannerState();
}

class _PointsEarnedBannerState extends State<_PointsEarnedBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _ac, curve: Curves.elasticOut);
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.85, end: 1.0).animate(_scale),
      child: PbsCard(
        color: AppColors.studentGreen,
        border: Border.all(color: AppColors.studentGreen),
        padding: const EdgeInsets.all(AppSizes.lg),
        onTap: widget.onTapStore,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '+${widget.earned}P 획득!',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '오늘 자기점검 참여 보상',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
            if (widget.hasWeeklyBonus) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      '월~금 개근 보너스 +500P 포함!',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_bag_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '내 잔액 ${NumberFormat('#,###').format(widget.totalBalance)}P · 교환소에서 사용 가능',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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
