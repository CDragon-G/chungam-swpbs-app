import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../school/models/school_rule.dart';
import '../../school/providers/school_provider.dart';

class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({super.key});

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  bool _reordering = false;

  /// Reassign order_index across ALL rules so that the new space order persists.
  /// Rules within each space keep their original relative order.
  Future<void> _reorderSpaces({
    required List<String> spaces,
    required Map<String, List<SchoolRule>> grouped,
    required int oldIdx,
    required int newIdx,
  }) async {
    if (newIdx > oldIdx) newIdx -= 1;
    if (oldIdx == newIdx) return;

    final newOrder = [...spaces];
    final moved = newOrder.removeAt(oldIdx);
    newOrder.insert(newIdx, moved);

    final flat = <SchoolRule>[];
    for (final s in newOrder) {
      final spaceRules = [...(grouped[s] ?? const <SchoolRule>[])];
      spaceRules.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      flat.addAll(spaceRules);
    }

    setState(() => _reordering = true);
    try {
      await ref.read(schoolRepositoryProvider).reorderRules(flat);
      ref.invalidate(allSchoolRulesProvider);
      ref.invalidate(schoolRulesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('순서 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(allSchoolRulesProvider);
    final profile = ref.watch(profileProvider).value;
    final canEdit = profile?.isAdminTeacher ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          canEdit ? '규칙 설정' : '규칙 (읽기 전용)',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (_reordering)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (canEdit)
            IconButton(
              tooltip: '규칙 추가',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showAddSheet(context, ref),
            ),
        ],
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (rules) {
          final grouped = groupBy(rules, (r) => r.space);
          // Sort spaces by min order_index of their rules
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

          if (canEdit) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.all(AppSizes.lg),
              buildDefaultDragHandles: false,
              header: const _VoteLinkBanner(),
              itemCount: spaces.length,
              onReorder: (oldIdx, newIdx) => _reorderSpaces(
                spaces: spaces,
                grouped: grouped,
                oldIdx: oldIdx,
                newIdx: newIdx,
              ),
              itemBuilder: (context, i) {
                final s = spaces[i];
                return _SpaceGroup(
                  key: ValueKey(s),
                  space: s,
                  rules: grouped[s] ?? const [],
                  outerIndex: i,
                  canEdit: true,
                );
              },
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: spaces.length,
            itemBuilder: (context, i) {
              final s = spaces[i];
              return _SpaceGroup(
                key: ValueKey(s),
                space: s,
                rules: grouped[s] ?? const [],
                outerIndex: i,
                canEdit: false,
              );
            },
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(_).viewInsets.bottom,
        ),
        child: const _AddRuleSheet(),
      ),
    );
  }
}

// Backward-compat wrapper: outerIndex is required by _SpaceGroup.
// (declared above; left here as a marker)

/// '수업' 규칙 ↔ 🍽️ 수업맛집 연계 안내.
class _VoteLinkBanner extends StatelessWidget {
  const _VoteLinkBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🍽️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "'수업' 공간의 규칙은 수업맛집 투표와 연계돼요. "
              '교사들이 매주 이 규칙을 가장 잘 실천한 학급에 투표하고, '
              '학기별 수업맛집 학급을 선정해 강화(현판·간식 등)할 수 있어요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                height: 1.5,
                color: const Color(0xFF9F1239),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceGroup extends ConsumerStatefulWidget {
  const _SpaceGroup({
    super.key,
    required this.space,
    required this.rules,
    required this.outerIndex,
    required this.canEdit,
  });
  final String space;
  final List<SchoolRule> rules;
  final int outerIndex;
  final bool canEdit;

  @override
  ConsumerState<_SpaceGroup> createState() => _SpaceGroupState();
}

class _SpaceGroupState extends ConsumerState<_SpaceGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.rules]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: PbsCard(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          children: [
            Row(
              children: [
                // Drag handle for outer (space) reordering — admin only
                if (widget.canEdit)
                  ReorderableDragStartListener(
                    index: widget.outerIndex,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 22,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppColors.spaceColor(widget.space),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.space,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${sorted.length}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded)
              if (widget.canEdit)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  onReorder: (oldIdx, newIdx) async {
                    if (newIdx > oldIdx) newIdx -= 1;
                    final reordered = [...sorted];
                    final item = reordered.removeAt(oldIdx);
                    reordered.insert(newIdx, item);
                    await ref
                        .read(schoolRepositoryProvider)
                        .reorderRules(reordered);
                    ref.invalidate(allSchoolRulesProvider);
                    ref.invalidate(schoolRulesProvider);
                  },
                  children: [
                    for (final r in sorted)
                      _RuleTile(key: ValueKey(r.id), rule: r, canEdit: true),
                  ],
                )
              else
                Column(
                  children: [
                    for (final r in sorted)
                      _RuleTile(key: ValueKey(r.id), rule: r, canEdit: false),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({super.key, required this.rule, required this.canEdit});
  final SchoolRule rule;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.categoryColor(rule.category).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rule.category,
        style: GoogleFonts.notoSansKr(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.categoryColor(rule.category),
        ),
      ),
    );

    final ruleText = Text(
      rule.ruleText,
      style: GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.4,
        color:
            rule.isActive ? AppColors.textPrimary : AppColors.textTertiary,
        decoration: rule.isActive ? null : TextDecoration.lineThrough,
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: rule.isActive ? AppColors.background : AppColors.borderLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: canEdit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      categoryBadge,
                      const SizedBox(height: 4),
                      ruleText,
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: rule.isActive,
                    onChanged: (v) async {
                      await ref
                          .read(schoolRepositoryProvider)
                          .updateRule(rule.id, {'is_active': v});
                      ref.invalidate(allSchoolRulesProvider);
                      ref.invalidate(schoolRulesProvider);
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (value) async {
                    if (value == 'edit') {
                      _showEdit(context, ref, rule);
                    } else if (value == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('삭제하시겠어요?'),
                          content: const Text(
                              '규칙을 영구 삭제합니다. 이미 등록된 학생 응답 데이터는 유지됩니다.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref
                            .read(schoolRepositoryProvider)
                            .deleteRule(rule.id);
                        ref.invalidate(allSchoolRulesProvider);
                        ref.invalidate(schoolRulesProvider);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('편집'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.danger),
                          SizedBox(width: 8),
                          Text('삭제',
                              style: TextStyle(color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                categoryBadge,
                const SizedBox(width: 8),
                Expanded(child: ruleText),
              ],
            ),
    );
  }

  void _showEdit(BuildContext context, WidgetRef ref, SchoolRule rule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
        child: _AddRuleSheet(existing: rule),
      ),
    );
  }
}

class _AddRuleSheet extends ConsumerStatefulWidget {
  const _AddRuleSheet({this.existing});
  final SchoolRule? existing;

  @override
  ConsumerState<_AddRuleSheet> createState() => _AddRuleSheetState();
}

class _AddRuleSheetState extends ConsumerState<_AddRuleSheet> {
  late String _space;
  late String _category;
  late final TextEditingController _text;
  late final TextEditingController _customSpace;
  bool _useCustomSpace = false;
  bool _saving = false;

  /// 기본 공간 + 이 학교가 이미 만들어 쓰는 커스텀 공간 (예: 쉼터, 도서관)
  List<String> get _allSpaces {
    final rules = ref.read(allSchoolRulesProvider).value ?? [];
    final custom = rules
        .map((r) => r.space)
        .where((s) => !AppStrings.spaces.contains(s))
        .toSet()
        .toList()
      ..sort();
    return [...AppStrings.spaces, ...custom];
  }

  @override
  void initState() {
    super.initState();
    _space = widget.existing?.space ?? AppStrings.spaces.first;
    _category = widget.existing?.category ??
        (widget.existing?.space == '수업'
            ? AppStrings.lessonCategories.first
            : AppStrings.mrsCategories.first);
    _text = TextEditingController(text: widget.existing?.ruleText ?? '');
    _customSpace = TextEditingController();
  }

  @override
  void dispose() {
    _text.dispose();
    _customSpace.dispose();
    super.dispose();
  }

  List<String> get _categoriesForSpace =>
      _space == '수업' ? AppStrings.lessonCategories : AppStrings.mrsCategories;

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) return;
    if (_useCustomSpace) {
      final name = _customSpace.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('새 공간 이름을 입력해주세요.')),
        );
        return;
      }
      _space = name;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(schoolRepositoryProvider);
      final profile = ref.read(profileProvider).value;
      if (profile?.schoolId == null) return;
      if (widget.existing == null) {
        final rules = ref.read(allSchoolRulesProvider).value ?? [];
        await repo.addRule(
          schoolId: profile!.schoolId!,
          space: _space,
          category: _category,
          ruleText: _text.text.trim(),
          orderIndex: rules.length,
        );
      } else {
        await repo.updateRule(widget.existing!.id, {
          'space': _space,
          'category': _category,
          'rule_text': _text.text.trim(),
        });
      }
      ref.invalidate(allSchoolRulesProvider);
      ref.invalidate(schoolRulesProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? '새 규칙 추가' : '규칙 편집',
            style: GoogleFonts.notoSansKr(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text(
            '공간',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ..._allSpaces.map((sp) {
                final selected = !_useCustomSpace && _space == sp;
                return ChoiceChip(
                  label: Text(sp),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _useCustomSpace = false;
                      _space = sp;
                      _category = _categoriesForSpace.first;
                    });
                  },
                  selectedColor: AppColors.spaceColor(sp),
                  labelStyle: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: AppColors.borderLight),
                  ),
                );
              }),
              // 학교별 커스텀 공간 — 예: 쉼터, 도서관, 운동장
              ChoiceChip(
                label: const Text('➕ 새 공간'),
                selected: _useCustomSpace,
                onSelected: (_) => setState(() {
                  _useCustomSpace = true;
                  _category = AppStrings.mrsCategories.first;
                }),
                selectedColor: AppColors.primary,
                labelStyle: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color:
                      _useCustomSpace ? Colors.white : AppColors.textPrimary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: AppColors.borderLight),
                ),
              ),
            ],
          ),
          if (_useCustomSpace) ...[
            const SizedBox(height: 8),
            PbsTextField(
              controller: _customSpace,
              label: '새 공간 이름',
              hint: '예: 쉼터, 도서관, 운동장',
            ),
          ],
          const SizedBox(height: AppSizes.md),
          Text(
            '카테고리',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: _categoriesForSpace.map((c) {
              final selected = _category == c;
              return ChoiceChip(
                label: Text(c),
                selected: selected,
                onSelected: (_) => setState(() => _category = c),
                selectedColor: AppColors.categoryColor(c),
                labelStyle: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: AppColors.borderLight),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSizes.md),
          PbsTextField(
            controller: _text,
            label: '규칙 내용',
            hint: '예: 수업 시작 종이 칠 때까지 자리에 앉아 있어요',
          ),
          const SizedBox(height: AppSizes.lg),
          PbsPrimaryButton(
            label: widget.existing == null ? '추가' : '저장',
            color: AppColors.teacherNavy,
            loading: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: AppSizes.md),
        ],
      ),
    );
  }
}
