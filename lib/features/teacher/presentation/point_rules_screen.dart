import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';

// ══════════════════ 모델 ══════════════════

class PointRule {
  const PointRule({
    required this.reason,
    required this.label,
    required this.hint,
    required this.amount,
    required this.defaultAmount,
    required this.min,
    required this.max,
    required this.step,
  });

  final String reason;
  final String label;
  final String hint;
  final int amount;
  final int defaultAmount;
  final int min;
  final int max;
  final int step;

  bool get isDefault => amount == defaultAmount;
  int get divisions => ((max - min) / step).round().clamp(1, 1000);

  factory PointRule.fromMap(Map<String, dynamic> m) => PointRule(
        reason: m['reason'] as String,
        label: (m['label'] as String?) ?? '',
        hint: (m['hint'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        defaultAmount: (m['default'] as num?)?.toInt() ?? 0,
        min: (m['min'] as num?)?.toInt() ?? 0,
        max: (m['max'] as num?)?.toInt() ?? 100,
        step: (m['step'] as num?)?.toInt() ?? 10,
      );
}

class PointRules {
  const PointRules({required this.canEdit, required this.items});
  final bool canEdit;
  final List<PointRule> items;
}

final pointRulesProvider = FutureProvider<PointRules>((ref) async {
  final res = await SupabaseService.client.rpc('point_rules');
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) {
    throw StateError(m['error'] as String? ?? '불러오지 못했어요');
  }
  return PointRules(
    canEdit: m['can_edit'] == true,
    items: ((m['items'] as List?) ?? const [])
        .map((e) => PointRule.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
});

// ══════════════════ 화면 ══════════════════

/// ⚙️ 포인트 설정 — 무엇을 하면 몇 점을 줄지 학교가 정한다.
/// 앱을 새로 받지 않아도 바로 반영된다.
class PointRulesScreen extends ConsumerWidget {
  const PointRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pointRulesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/teacher/dashboard'),
        ),
        title: Text('포인트 설정',
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(translateError(e),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
          ),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            PbsCard(
              color: const Color(0xFFF5F3FF),
              child: Text(
                data.canEdit
                    ? '학생이 무엇을 하면 몇 점을 받을지 정합니다.\n'
                        '바꾸면 그때부터 지급되는 포인트에 바로 적용돼요. '
                        '이미 받은 포인트는 그대로입니다.'
                    : '우리 학교의 포인트 기준이에요.\n'
                        '값을 바꾸는 것은 관리자 선생님만 할 수 있어요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5,
                    height: 1.6,
                    color: const Color(0xFF5B21B6)),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            for (final rule in data.items)
              _RuleCard(rule: rule, canEdit: data.canEdit),
            const SizedBox(height: AppSizes.md),
            Text(
              '0으로 두면 그 활동에는 포인트를 주지 않습니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSizes.xxxl),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends ConsumerStatefulWidget {
  const _RuleCard({required this.rule, required this.canEdit});
  final PointRule rule;
  final bool canEdit;

  @override
  ConsumerState<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends ConsumerState<_RuleCard> {
  late double _value = widget.rule.amount.toDouble();
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _RuleCard old) {
    super.didUpdateWidget(old);
    if (old.rule.amount != widget.rule.amount && !_saving) {
      _value = widget.rule.amount.toDouble();
    }
  }

  Future<void> _save(int? amount) async {
    setState(() => _saving = true);
    try {
      final res = await SupabaseService.client.rpc('set_point_rule', params: {
        'p_reason': widget.rule.reason,
        'p_amount': amount,
      });
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) {
        throw StateError(m['error'] as String? ?? '바꾸지 못했어요');
      }
      final saved = (m['amount'] as num?)?.toInt() ?? widget.rule.amount;
      if (mounted) setState(() => _value = saved.toDouble());
      ref.invalidate(pointRulesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.rule.label} ${saved}P로 정했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _value = widget.rule.amount.toDouble());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;
    final current = _value.round();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 15, fontWeight: FontWeight.w900)),
                      Text(r.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11.5, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('$current P',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7C3AED))),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF7C3AED),
                thumbColor: const Color(0xFF7C3AED),
                inactiveTrackColor: const Color(0xFFEDE9FE),
                valueIndicatorColor: const Color(0xFF7C3AED),
                trackHeight: 5,
              ),
              child: Slider(
                value: _value.clamp(r.min.toDouble(), r.max.toDouble()),
                min: r.min.toDouble(),
                max: r.max.toDouble(),
                divisions: r.divisions,
                label: '$current P',
                onChanged: widget.canEdit && !_saving
                    ? (v) => setState(() => _value = v)
                    : null,
                onChangeEnd:
                    widget.canEdit && !_saving ? (v) => _save(v.round()) : null,
              ),
            ),
            Row(
              children: [
                Text('${r.min}P',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textTertiary)),
                const Spacer(),
                if (current != r.defaultAmount && widget.canEdit)
                  TextButton(
                    onPressed: _saving ? null : () => _save(null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text('기본값 ${r.defaultAmount}P로',
                        style: GoogleFonts.notoSansKr(fontSize: 11.5)),
                  )
                else
                  Text(r.isDefault ? '기본값' : '',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11, color: AppColors.textTertiary)),
                const Spacer(),
                Text('${r.max}P',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
