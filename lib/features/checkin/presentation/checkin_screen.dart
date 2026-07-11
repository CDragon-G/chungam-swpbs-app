import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../../school/models/school_rule.dart';
import '../../school/providers/school_provider.dart';
import '../../points/providers/points_provider.dart';
import '../../student/providers/badge_provider.dart';
import '../../student/providers/student_stats_provider.dart';
import '../providers/checkin_provider.dart';

class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key});

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends ConsumerState<CheckinScreen>
    with TickerProviderStateMixin {
  // Local state: ruleId -> true(kept) / false(missed) / null(no answer)
  final Map<String, bool?> _answers = {};
  bool _seeded = false;
  bool _submitting = false;
  TabController? _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    // Refresh rules + today's check-in on every entry so we always show
    // the latest order/edits made by teachers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(schoolRulesProvider);
      ref.invalidate(todayCheckinProvider);
    });
  }

  void _ensureTabController(int length) {
    if (_tabController != null && _tabController!.length == length) return;
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    _tabController = TabController(length: length, vsync: this);
    _tabController!.addListener(_onTabChanged);
    _currentTab = 0;
  }

  void _onTabChanged() {
    if (_tabController == null) return;
    if (_tabController!.indexIsChanging) return;
    if (_currentTab != _tabController!.index) {
      setState(() => _currentTab = _tabController!.index);
    }
  }

  bool get _isLastTab =>
      _tabController == null || _currentTab >= _tabController!.length - 1;

  void _goNextTab() {
    if (_tabController != null && _currentTab < _tabController!.length - 1) {
      _tabController!.animateTo(_currentTab + 1);
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _setAnswer(String ruleId, bool value) {
    setState(() {
      _answers[ruleId] = value;
    });
  }

  void _seedIfNeeded(List<SchoolRule> rules) {
    if (_seeded || rules.isEmpty) return;
    final today = ref.read(todayCheckinProvider).value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seeded) return;
      setState(() {
        for (final r in rules) {
          _answers[r.id] = today?.answers[r.id];
        }
        _seeded = true;
      });
    });
  }

  Future<void> _onSubmit() async {
    final clean = <String, bool>{
      for (final e in _answers.entries)
        if (e.value != null) e.key: e.value!,
    };
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('한 항목 이상 응답해주세요.')),
      );
      return;
    }

    final profile = ref.read(profileProvider).value;
    final rules = ref.read(schoolRulesProvider).value ?? const <SchoolRule>[];
    if (profile?.schoolId == null) return;

    final existing = ref.read(todayCheckinProvider).value;
    if (existing != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('오늘 이미 점검했어요'),
          content: const Text('기존 응답을 새 응답으로 덮어쓸까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('덮어쓰기'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _submitting = true);
    try {
      final result = await ref.read(checkinRepositoryProvider).submit(
            schoolId: profile!.schoolId!,
            rules: rules,
            answers: clean,
            comment: null,
          );
      // Award points (idempotent at DB level)
      try {
        await ref.read(pointsRepositoryProvider).awardCheckinPoints(
              userId: result.checkin.userId,
              schoolId: result.checkin.schoolId,
              checkinDate: result.checkin.checkinDate,
            );
      } catch (_) {/* don't block on point award failure */}
      ref.invalidate(todayCheckinProvider);
      ref.invalidate(studentStatsProvider);
      ref.invalidate(checkinHistoryProvider);
      ref.invalidate(myPointsProvider);
      ref.invalidate(myPointsHistoryProvider);
      await evaluateAndAwardBadges(ref);
      if (!mounted) return;
      celebrateGrowth(context, ref, headline: '오늘의 자기점검 완료! ✅');
      context.go('/student/checkin/result');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translateError(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(schoolRulesProvider);

    return rulesAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(
              translateError(e),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(color: AppColors.danger),
            ),
          ),
        ),
      ),
      data: (rules) {
        if (rules.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/student/home'),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Text(
                  '아직 학교 규칙이 설정되지 않았어요.\n담임선생님께 문의해주세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }

        _seedIfNeeded(rules);

        final grouped = groupBy(rules, (r) => r.space);
        // Sort spaces by the minimum order_index of their rules
        // (matches teacher's rule_editor ordering exactly).
        final spaces = grouped.keys.toList()
          ..sort((a, b) {
            final minA = grouped[a]!
                .map((r) => r.orderIndex)
                .reduce((x, y) => x < y ? x : y);
            final minB = grouped[b]!
                .map((r) => r.orderIndex)
                .reduce((x, y) => x < y ? x : y);
            return minA.compareTo(minB);
          });
        final answered = _answers.values.where((v) => v != null).length;
        final total = rules.length;

        _ensureTabController(spaces.length);

        // Per-space answered counts for tab labels
        final perSpaceAnswered = <String, int>{};
        for (final s in spaces) {
          perSpaceAnswered[s] = (grouped[s] ?? const [])
              .where((r) => _answers[r.id] != null)
              .length;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go('/student/home'),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘 자기점검',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$answered / $total 완료 · ${_currentTab + 1}/${spaces.length} 카테고리',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: AppColors.studentGreen,
                  labelColor: AppColors.studentGreen,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: [
                    for (final s in spaces)
                      Tab(
                        text:
                            '$s  ${perSpaceAnswered[s]}/${(grouped[s] ?? const []).length}',
                      ),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              LinearProgressIndicator(
                value: total == 0 ? 0 : answered / total,
                backgroundColor: AppColors.borderLight,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.studentGreen),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final s in spaces)
                      _RuleList(
                        rules: grouped[s] ?? const [],
                        answers: _answers,
                        onToggle: _setAnswer,
                      ),
                  ],
                ),
              ),
              _BottomNavBar(
                isLastTab: _isLastTab,
                submitting: _submitting,
                onNext: _goNextTab,
                onSubmit: _onSubmit,
                nextLabel: _isLastTab
                    ? '오늘 점검 완료하기'
                    : '다음: ${spaces[(_currentTab + 1).clamp(0, spaces.length - 1)]}',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.isLastTab,
    required this.submitting,
    required this.onNext,
    required this.onSubmit,
    required this.nextLabel,
  });

  final bool isLastTab;
  final bool submitting;
  final VoidCallback onNext;
  final VoidCallback onSubmit;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.md,
          AppSizes.lg,
          AppSizes.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: PbsPrimaryButton(
          label: nextLabel,
          icon: isLastTab
              ? Icons.check_circle_outline_rounded
              : Icons.arrow_forward_rounded,
          color: AppColors.studentGreen,
          loading: submitting,
          onPressed: isLastTab ? onSubmit : onNext,
        ),
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  const _RuleList({
    required this.rules,
    required this.answers,
    required this.onToggle,
  });

  final List<SchoolRule> rules;
  final Map<String, bool?> answers;
  final void Function(String ruleId, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.xxxl,
      ),
      itemCount: rules.length,
      itemBuilder: (context, i) {
        final r = rules[i];
        final value = answers[r.id];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.md),
          child: PbsCard(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.categoryColor(r.category)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r.category,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.categoryColor(r.category),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r.ruleText,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Row(
                  children: [
                    Expanded(
                      child: _OXButton(
                        label: 'O  잘 지켰어요',
                        selected: value == true,
                        color: AppColors.success,
                        onTap: () => onToggle(r.id, true),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: _OXButton(
                        label: 'X  미흡했어요',
                        selected: value == false,
                        color: AppColors.danger,
                        onTap: () => onToggle(r.id, false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OXButton extends StatelessWidget {
  const _OXButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Material + InkWell wrapping for guaranteed tap handling
    return Material(
      color: selected ? color : AppColors.background,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
