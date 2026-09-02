import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';

/// 규칙 하나에 대한 O/X 집계.
class RuleStat {
  const RuleStat({
    required this.id,
    required this.space,
    required this.ruleText,
    required this.total,
    required this.kept,
    required this.keptPct,
  });

  final String id;
  final String space;
  final String ruleText;

  /// 이 규칙이 점검된 횟수 (O + X)
  final int total;

  /// 지켰다고 답한 횟수 (O)
  final int kept;
  final int keptPct;

  int get broken => total - kept;

  factory RuleStat.fromMap(Map<String, dynamic> m) => RuleStat(
        id: m['id'] as String,
        space: (m['space'] as String?) ?? '',
        ruleText: (m['rule_text'] as String?) ?? '',
        total: (m['total'] as num?)?.toInt() ?? 0,
        kept: (m['kept'] as num?)?.toInt() ?? 0,
        keptPct: (m['kept_pct'] as num?)?.toInt() ?? 0,
      );
}

final ruleStatsDaysProvider = StateProvider<int>((_) => 30);

final ruleStatsProvider = FutureProvider<List<RuleStat>>((ref) async {
  final days = ref.watch(ruleStatsDaysProvider);
  final res = await SupabaseService.client
      .rpc('rule_compliance_stats', params: {'p_days': days});
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) {
    throw StateError(m['error'] as String? ?? '불러오지 못했어요');
  }
  return ((m['rules'] as List?) ?? const [])
      .map((e) => RuleStat.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// 📋 규칙별 실천 현황 — 어떤 규칙이 잘 지켜지고 어떤 규칙이 어려운지.
/// SWPBS에서 재교육 대상 규칙을 고르는 근거가 된다.
class RuleStatsScreen extends ConsumerWidget {
  const RuleStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(ruleStatsDaysProvider);
    final stats = ref.watch(ruleStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📋 규칙별 실천 현황',
                style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('O 지켰어요 · X 못 지켰어요',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ruleStatsProvider),
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            Row(
              children: [
                for (final d in const [7, 30, 90])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () =>
                            ref.read(ruleStatsDaysProvider.notifier).state = d,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: days == d
                                ? AppColors.teacherNavy
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          alignment: Alignment.center,
                          child: Text('최근 $d일',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: days == d
                                      ? Colors.white
                                      : AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            stats.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => PbsCard(child: Text(translateError(e))),
              data: (list) {
                if (list.isEmpty) {
                  return PbsCard(
                    child: Text(
                      '아직 집계할 기록이 부족해요.\n'
                      '규칙마다 5회 이상 점검돼야 통계가 나옵니다.',
                      style:
                          GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
                    ),
                  );
                }
                // 서버가 지킨 비율 오름차순으로 준다 → 어려운 규칙이 위로
                final hard = list.where((r) => r.keptPct < 70).toList();
                final good = list.where((r) => r.keptPct >= 90).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hard.isNotEmpty) ...[
                      _Summary(
                        emoji: '⚠️',
                        color: AppColors.danger,
                        title: '가장 어려운 규칙',
                        body: hard.first.ruleText,
                        sub: '${hard.first.keptPct}% 만 지켜졌어요 '
                            '(X ${hard.first.broken}회)',
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (good.isNotEmpty)
                      _Summary(
                        emoji: '🌟',
                        color: AppColors.success,
                        title: '가장 잘 지켜지는 규칙',
                        body: good.last.ruleText,
                        sub: '${good.last.keptPct}% 가 지켰어요',
                      ),
                    const SectionHeader(title: '전체 규칙'),
                    ...list.map((r) => _RuleRow(stat: r)),
                    const SizedBox(height: AppSizes.lg),
                    PbsCard(
                      color: AppColors.teacherNavyLight,
                      child: Text(
                        '70% 미만인 규칙은 재교육이 필요하다는 신호예요.\n'
                        '규칙이 어려운지, 안내가 부족한지, 환경이 문제인지 살펴보세요.',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5,
                            height: 1.6,
                            color: AppColors.teacherNavy),
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxxl),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.emoji,
    required this.color,
    required this.title,
    required this.body,
    required this.sub,
  });
  final String emoji;
  final Color color;
  final String title;
  final String body;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return PbsCard(
      color: color.withValues(alpha: 0.07),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(title,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: GoogleFonts.notoSansKr(
                  fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 2),
          Text(sub,
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.stat});
  final RuleStat stat;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreColor(stat.keptPct.toDouble());
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PbsCard(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stat.space.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6, top: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(stat.space,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary)),
                  ),
                Expanded(
                  child: Text(stat.ruleText,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, height: 1.45)),
                ),
                const SizedBox(width: 8),
                Text('${stat.keptPct}%',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (stat.keptPct / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('O ${stat.kept}회  ·  X ${stat.broken}회  ·  총 ${stat.total}회',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}
