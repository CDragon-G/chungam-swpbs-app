import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../models/hof_entry.dart';
import '../providers/hof_provider.dart';

/// 명예의 전당 — 이달의 학생 (전교 / 학년 / 학급).
class HallOfFameScreen extends ConsumerWidget {
  const HallOfFameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hofAsync = ref.watch(hallOfFameProvider);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏆 명예의 전당',
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '우리 학교 새싹을 가장 많이 키운 친구들',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(hallOfFameProvider),
        child: hofAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text(translateError(e))),
            ),
          ]),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      '이번 달 활동 기록이 아직 없어요.\n매일 점검하고 칭찬받으면\n이달의 학생이 될 수 있어요! 🌱',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary, height: 1.6),
                    ),
                  ),
                ),
              ]);
            }
            final school = entries.where((e) => e.scope == 'school').toList();
            final grades = entries.where((e) => e.scope == 'grade').toList();
            final classes = entries.where((e) => e.scope == 'class').toList();
            return ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                Text(
                  '${now.year}년 ${now.month}월 · 새싹에 양분을 가장 많이 준 주인공들',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                // 전교 1위 — 명예 식집사
                if (school.isNotEmpty) _TopCard(entry: school.first),
                if (grades.isNotEmpty) ...[
                  const SectionHeader(title: '🌿 학년 대표 식집사'),
                  ...grades.map((e) => _RankRow(
                      entry: e, title: '학년 대표 식집사', emoji: '🌿')),
                ],
                if (classes.isNotEmpty) ...[
                  const SectionHeader(title: '💧 우리 반 새싹 지킴이'),
                  ...classes.map((e) => _RankRow(
                      entry: e, title: '새싹 지킴이', emoji: '💧')),
                ],
                const SizedBox(height: 12),
                Text(
                  '🌱 양분 점수 = 칭찬 40% + 꾸준한 참여 30% + 점검 점수 30%',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.entry});
  final HofEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.studentGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Image.asset('assets/growth/stage7.png',
              width: 64, height: 64,
              errorBuilder: (_, __, ___) =>
                  const Text('👑', style: TextStyle(fontSize: 44))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('🏆 이달의 명예 식집사',
                style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(height: 8),
          Text(
            entry.maskedName,
            style: GoogleFonts.notoSansKr(
                fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          Text(
            entry.classLabel,
            style: GoogleFonts.notoSansKr(
                fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            '우리 학교 새싹에 가장 많은 양분을 준 주인공! 🌱',
            style: GoogleFonts.notoSansKr(
                fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('칭찬', '${entry.praiseCount}회'),
              _statDivider(),
              _stat('점검', '${entry.checkinDays}일'),
              _statDivider(),
              _stat('평균', '${entry.avgScore.round()}점'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value,
              style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          Text(label,
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: Colors.white70)),
        ],
      );

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: Colors.white24);
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.entry,
    this.title = '식집사',
    this.emoji = '🌟',
  });
  final HofEntry entry;
  final String title;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.scopeLabel,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Text(emoji, style: GoogleFonts.notoSansKr(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.maskedName} (${entry.classLabel}) · $title',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '칭찬 ${entry.praiseCount}회 · 점검 ${entry.checkinDays}일 · 평균 ${entry.avgScore.round()}점',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.totalScore.round()}',
              style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.studentGreen),
            ),
          ],
        ),
      ),
    );
  }
}
