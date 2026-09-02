import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/category_radar_chart.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../honor/honor_gardener.dart';
import '../providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _State();
}

class _State extends ConsumerState<DashboardScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '대시보드',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
            child: Row(
              children: [
                for (final (i, label)
                    in const ['전체', '반별', '학생별'].indexed)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tab == i
                              ? AppColors.teacherNavy
                              : AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _tab == i
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: switch (_tab) {
        0 => const _OverallTab(),
        1 => const _PerClassTab(),
        _ => const _PerStudentTab(),
      },
    );
  }
}

class _OverallTab extends ConsumerWidget {
  const _OverallTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(schoolOverviewProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(schoolOverviewProvider),
      child: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (o) => ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            HonorGardenerCard(
                isAdmin: ref.watch(profileProvider).value?.isAdminTeacher ?? false),
            PbsCard(
              color: AppColors.teacherNavyLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '이번 주 참여율 ${o.weeklyAvg.round()}%',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.teacherNavy,
                    ),
                  ),
                  Text(
                    '지난주 대비 ${o.weekDelta >= 0 ? '+' : ''}${o.weekDelta.toStringAsFixed(1)}%',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: o.weekDelta >= 0
                          ? AppColors.success
                          : AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader(title: '최근 2주 참여 추이'),
            PbsCard(
              child: SizedBox(height: 200, child: _TrendLine(data: o.last14Days)),
            ),
            const SectionHeader(title: '반별 참여율'),
            PbsCard(child: _ClassBars(data: o.classParticipation)),
            const SectionHeader(title: '카테고리 평균'),
            PbsCard(child: CategoryRadarChart(scores: o.categoryAverages)),
            const SizedBox(height: AppSizes.lg),
            // 규칙별 O/X 통계와 학생 건의함으로 가는 길
            OutlinedButton.icon(
              onPressed: () => context.go('/teacher/rule-stats'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teacherNavy,
                side: const BorderSide(color: AppColors.teacherNavy),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.rule_rounded, size: 18),
              label: Text('규칙별 실천 현황 보기',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
            if (ref.watch(profileProvider).value?.isAdminTeacher ?? false) ...[
              const SizedBox(height: AppSizes.sm),
              OutlinedButton.icon(
                onPressed: () => context.go('/teacher/suggestions'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teacherNavy,
                  side: const BorderSide(color: AppColors.teacherNavy),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.mark_email_unread_rounded, size: 18),
                label: Text('학생 규칙 건의함',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(height: AppSizes.xxxl),
          ],
        ),
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.data});
  final List<({DateTime date, double avg, int participants})> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('데이터 없음'));
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].avg),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
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
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 3,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    KstDate.formatShort(data[i].date),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.teacherNavy,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.teacherNavy.withValues(alpha: 0.22),
                  AppColors.teacherNavy.withValues(alpha: 0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 반별 참여율 — 가로 막대.
/// 세로 막대일 때는 학급이 많으면 아래 라벨이 서로 겹쳐 읽을 수 없었다.
/// 한 학급이 한 줄을 차지하게 눕히고, 학년이 바뀌면 사이를 띄운다.
class _ClassBars extends StatelessWidget {
  const _ClassBars({required this.data});
  final Map<String, double> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('데이터 없음',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13, color: AppColors.textTertiary)),
        ),
      );
    }

    // '1-3' 처럼 학년-반 형태를 숫자로 정렬한다 (문자열 정렬이면 10반이 2반 앞에 온다)
    int gradeOf(String k) => int.tryParse(k.split('-').first) ?? 0;
    int classOf(String k) =>
        int.tryParse(k.split('-').length > 1 ? k.split('-')[1] : '') ?? 0;

    final entries = data.entries.toList()
      ..sort((a, b) {
        final g = gradeOf(a.key).compareTo(gradeOf(b.key));
        return g != 0 ? g : classOf(a.key).compareTo(classOf(b.key));
      });

    final rows = <Widget>[];
    int? prevGrade;
    for (final e in entries) {
      final g = gradeOf(e.key);
      if (prevGrade != null && g != prevGrade) {
        rows.add(const SizedBox(height: 10));
      }
      prevGrade = g;
      rows.add(_ClassBarRow(label: e.key, value: e.value));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _ClassBarRow extends StatelessWidget {
  const _ClassBarRow({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreColor(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary),
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
                  widthFactor: (value / 100).clamp(0.02, 1.0),
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
          SizedBox(
            width: 42,
            child: Text(
              '${value.round()}%',
              textAlign: TextAlign.right,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerClassTab extends ConsumerWidget {
  const _PerClassTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(schoolOverviewProvider);
    final selected = ref.watch(selectedClassProvider);

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (o) {
        final keys = o.classParticipation.keys.toList()..sort();
        if (keys.isEmpty) {
          return Center(
            child: Text(
              '학생이 가입되면 반별 분석이 표시돼요.',
              style: GoogleFonts.notoSansKr(color: AppColors.textTertiary),
            ),
          );
        }
        final current = selected ?? keys.first;
        if (selected == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedClassProvider.notifier).state = keys.first;
          });
        }
        return ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            // class dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: current,
                  isExpanded: true,
                  items: [
                    for (final k in keys)
                      DropdownMenuItem(
                        value: k,
                        child: Text(
                          '${k.split('-').first}학년 ${k.split('-').last}반',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(selectedClassProvider.notifier).state = v;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            _ClassDetail(classKey: current),
          ],
        );
      },
    );
  }
}

class _ClassDetail extends ConsumerWidget {
  const _ClassDetail({required this.classKey});
  final String classKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(classStatsProvider(classKey));
    return statsAsync.when(
      loading: () => const PbsCard(
        child: SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => PbsCard(child: Text('오류: $e')),
      data: (s) => Column(
        children: [
          const SectionHeader(title: '최근 14일 참여'),
          PbsCard(
            child: Row(
              children: [
                for (final d in s.participationByDay)
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 14,
                          height: 50 *
                              (d.total == 0
                                  ? 0.0
                                  : d.participants / d.total),
                          decoration: BoxDecoration(
                            color: AppColors.scoreColor(d.total == 0
                                ? 0
                                : (d.participants / d.total) * 100),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          KstDate.formatShort(d.date),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader(title: '카테고리 점수'),
          PbsCard(child: CategoryRadarChart(scores: s.categoryAverages)),
          const SectionHeader(title: '취약 규칙 Top 3'),
          PbsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: s.weakestRules.isEmpty
                  ? [
                      Text(
                        '데이터 없음',
                        style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ]
                  : s.weakestRules.map((r) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.text,
                                style: GoogleFonts.notoSansKr(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${(r.avgOk * 100).round()}%',
                              style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.w800,
                                color: AppColors.scoreColor(r.avgOk * 100),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          ),
          const SectionHeader(title: '오늘 미참여'),
          PbsCard(
            child: s.nonParticipantsToday.isEmpty
                ? Text(
                    '🎉 전원 참여!',
                    style: GoogleFonts.notoSansKr(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: s.nonParticipantsToday.map((np) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${np.grade}-${np.classNum}-${np.studentNum} ${np.nickname}',
                          style: GoogleFonts.notoSansKr(fontSize: 13),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _PerStudentTab extends ConsumerWidget {
  const _PerStudentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(studentRowsProvider);
    return rowsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text(
              '학생이 가입되면 여기에 표시돼요.',
              style: GoogleFonts.notoSansKr(color: AppColors.textTertiary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSizes.lg),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            final isAlert = r.missedDays >= 3;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: PbsCard(
                color: isAlert ? const Color(0xFFFFF1F2) : null,
                border: Border.all(
                  color: isAlert
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : AppColors.borderLight,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          isAlert ? AppColors.danger : AppColors.teacherNavy,
                      child: Text(
                        r.nickname.characters.isEmpty
                            ? '?'
                            : r.nickname.characters.first,
                        style: GoogleFonts.notoSansKr(
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
                            '${r.nickname} (${r.grade}-${r.classNum}-${r.studentNum})',
                            style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '🔥 연속 ${r.streak}일 · 평균 ${r.avgScore.round()}% · 🎖️ ${r.badgeCount}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (isAlert)
                            Text(
                              '⚠️ ${r.missedDays}일 연속 미참여',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.danger,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
