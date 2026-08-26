import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../models/point_exchange.dart';
import '../models/point_store_item.dart';
import '../providers/points_provider.dart';

class TeacherStoreScreen extends ConsumerStatefulWidget {
  const TeacherStoreScreen({super.key});

  @override
  ConsumerState<TeacherStoreScreen> createState() => _State();
}

class _State extends ConsumerState<TeacherStoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    // 관리자: 전교+학급 상품, 일반 교사: 자기 학급 상품 등록 가능
    final canEdit = profile?.isTeacher ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '포인트 교환소',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: '강화물 추가',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showItemSheet(context),
            ),
        ],
        bottom: TabBar(
          controller: _tc,
          indicatorColor: AppColors.teacherNavy,
          labelColor: AppColors.teacherNavy,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: '강화물 관리'),
            Tab(text: '교환 요청'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tc,
        children: const [
          _ItemsTab(),
          _ExchangesTab(),
        ],
      ),
    );
  }

  void _showItemSheet(BuildContext context, {PointStoreItem? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
        child: _AddItemSheet(existing: existing),
      ),
    );
  }
}

class _ItemsTab extends ConsumerWidget {
  const _ItemsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allStoreItemsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(allStoreItemsProvider),
      child: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(translateError(e))),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                const _EconomyPanel(),
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    '아직 등록된 강화물이 없어요.\n우측 상단 + 버튼으로 추가해주세요.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return const _EconomyPanel();
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: _ItemRow(item: items[i - 1]),
              );
            },
          );
        },
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});
  final PointStoreItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    // 관리자는 전부, 일반 교사는 자기가 등록한 상품만 관리
    final canManage = (profile?.isAdminTeacher ?? false) ||
        (item.createdBy != null && item.createdBy == profile?.userId);
    final card = PbsCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.isClassItem
                  ? AppColors.studentGreenLight
                  : AppColors.teacherNavyLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Text(item.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800,
                    color: item.isActive
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    decoration: item.isActive ? null : TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  item.isGroup
                      ? '함께 키우기 · 목표 ${item.costPoints}P'
                      : '${item.costPoints}P · 재고 ${item.isUnlimited ? "무제한" : item.stock}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    color: item.isClassItem
                        ? AppColors.studentGreen
                        : AppColors.textSecondary,
                    fontWeight:
                        item.isClassItem ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (item.createdByName != null)
                  Text(
                    '🧑‍🏫 등록: ${item.createdByName} 선생님',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (item.isGroup && item.isAchieved && !item.isClosed)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.celebration_rounded,
                            size: 14, color: AppColors.studentGreen),
                        const SizedBox(width: 4),
                        Text(
                          '목표 달성 — 지급 처리를 해주세요',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.studentGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!canManage)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                item.isActive ? '판매중' : '중지',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          if (canManage) ...[
          Switch.adaptive(
            value: item.isActive,
            onChanged: (v) async {
              await ref
                  .read(pointsRepositoryProvider)
                  .updateItem(item.id, {'is_active': v});
              ref.invalidate(allStoreItemsProvider);
              ref.invalidate(activeStoreItemsProvider);
            },
          ),
          // 편집·삭제를 하나의 메뉴로 통합 (규칙 탭과 동일 방식) → 공간 확보
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                size: 20, color: AppColors.textSecondary),
            padding: EdgeInsets.zero,
            onSelected: (v) async {
              if (v == 'edit') {
                _showEditSheet(context, item);
                return;
              }
              // 함께 키우기 — 지급 완료
              if (v == 'fulfill') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('지급 완료 처리'),
                    content: Text(
                        '${item.name} 을(를) 학급에 지급하셨나요?\n'
                        '처리하면 학생들에게 알림이 가고 목록에서 내려갑니다.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.studentGreen),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('지급 완료'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  await ref
                      .read(pointsRepositoryProvider)
                      .fulfillGroupItem(item.id);
                  ref.invalidate(allStoreItemsProvider);
                  ref.invalidate(activeStoreItemsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(translateError(e))),
                    );
                  }
                }
                return;
              }
              // 함께 키우기 — 취소하고 전액 환불
              if (v == 'refund') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('취소하고 환불'),
                    content: Text(
                        '${item.name} 을(를) 취소할까요?\n'
                        '학생들이 보탠 포인트를 전액 돌려드립니다.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('그만두기'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('취소하고 환불'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  final n = await ref
                      .read(pointsRepositoryProvider)
                      .cancelGroupItem(item.id);
                  ref.invalidate(allStoreItemsProvider);
                  ref.invalidate(activeStoreItemsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$n명에게 포인트를 돌려드렸어요.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(translateError(e))),
                    );
                  }
                }
                return;
              }
              // 삭제
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('강화물 삭제'),
                  content: Text(
                      '${item.name} 강화물을 삭제하시겠어요?\n이미 교환된 기록은 그대로 유지됩니다.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('삭제'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(pointsRepositoryProvider).deleteItem(item.id);
                ref.invalidate(allStoreItemsProvider);
                ref.invalidate(activeStoreItemsProvider);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('편집'),
                ]),
              ),
              if (item.isGroup && item.isAchieved && !item.isClosed)
                const PopupMenuItem(
                  value: 'fulfill',
                  child: Row(children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 18, color: AppColors.studentGreen),
                    SizedBox(width: 8),
                    Text('지급 완료',
                        style: TextStyle(color: AppColors.studentGreen)),
                  ]),
                ),
              if (item.isGroup && !item.isClosed)
                const PopupMenuItem(
                  value: 'refund',
                  child: Row(children: [
                    Icon(Icons.undo_rounded, size: 18, color: AppColors.warning),
                    SizedBox(width: 8),
                    Text('취소하고 환불',
                        style: TextStyle(color: AppColors.warning)),
                  ]),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('삭제', style: TextStyle(color: AppColors.danger)),
                ]),
              ),
            ],
          ),
          ],
        ],
      ),
    );
    // 🎀 좌상단 사선 리본 — 전교/학급 범위를 선물 포장 리본처럼 표시
    return Stack(
      children: [
        card,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: -30,
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Container(
                        width: 100,
                        alignment: Alignment.center,
                        padding:
                            const EdgeInsets.symmetric(vertical: 2.5),
                        color: item.isClassItem
                            ? AppColors.studentGreen
                            : AppColors.teacherNavy,
                        child: Text(
                          item.isClassItem
                              ? '${item.grade}-${item.classNum}'
                              : '전교',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
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
      ],
    );
  }

  void _showEditSheet(BuildContext context, PointStoreItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
        child: _AddItemSheet(existing: item),
      ),
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet({this.existing});
  final PointStoreItem? existing;

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

/// 강화물 아이콘 후보 — 간식·문구·쿠폰·특권·놀이 등 학교 보상에 인기 있는 이모지.
const kStoreEmojis = [
  '🎁', '🍫', '🍬', '🍭', '🍪', '🥤', '🧃', '🍦',
  '🍜', '🍕', '🍔', '🍩', '✏️', '📓', '🖊️', '📚',
  '🎟️', '🎫', '🎧', '🎵', '🎮', '⚽', '🏀', '🎲',
  '🪑', '⏰', '🏆', '⭐', '👑', '💝', '🍀', '📸',
];

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _maxPer;
  bool _isGroup = false;      // 함께 키우기 여부
  bool _capPerStudent = true; // 1인 한도를 둘 것인가
  bool _unlimited = true;
  bool _saving = false;
  String _emoji = '🎁';
  bool _schoolWide = true; // 전교 공통 vs 특정 학급
  int _grade = 1;
  int _classNum = 1;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _cost = TextEditingController(text: e?.costPoints.toString() ?? '');
    _stock = TextEditingController(text: e?.stock?.toString() ?? '');
    _maxPer = TextEditingController(text: e?.maxPerStudent?.toString() ?? '');
    _isGroup = e?.isGroup ?? false;
    _capPerStudent = e == null ? true : e.maxPerStudent != null;
    _unlimited = e?.stock == null;
    _emoji = e?.emoji ?? '🎁';
    if (e != null) {
      _schoolWide = !e.isClassItem;
      _grade = e.grade ?? 1;
      _classNum = e.classNum ?? 1;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _cost.dispose();
    _stock.dispose();
    _maxPer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final cost = int.tryParse(_cost.text);
    if (cost == null || cost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('포인트는 0 이상의 숫자여야 해요.')),
      );
      return;
    }
    // 함께 키우기는 재고 개념이 없다
    final stock = _isGroup ? null : (_unlimited ? null : int.tryParse(_stock.text));
    if (!_isGroup && !_unlimited && (stock == null || stock < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재고는 0 이상의 숫자여야 해요.')),
      );
      return;
    }

    int? maxPer;
    if (_isGroup) {
      if (cost <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('목표 포인트는 1 이상이어야 해요.')),
        );
        return;
      }
      if (_capPerStudent) {
        maxPer = int.tryParse(_maxPer.text);
        if (maxPer == null || maxPer <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('1인 최대 포인트를 입력해주세요.')),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(pointsRepositoryProvider);
      final profile = ref.read(profileProvider).value;
      if (profile?.schoolId == null) return;
      // 일반 교사는 전교 공통 불가 (서버 RLS도 차단하지만 UI에서 먼저)
      final isAdmin = profile!.isAdminTeacher;
      final schoolWide = isAdmin && _schoolWide;

      if (widget.existing == null) {
        final existing =
            ref.read(allStoreItemsProvider).value ?? const <PointStoreItem>[];
        await repo.createItem(
          schoolId: profile.schoolId!,
          name: _name.text.trim(),
          description:
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          costPoints: cost,
          stock: stock,
          orderIndex: existing.length,
          emoji: _emoji,
          grade: schoolWide ? null : _grade,
          classNum: schoolWide ? null : _classNum,
          createdByName: profile.nickname,
          itemType: _isGroup ? 'group' : 'individual',
          maxPerStudent: maxPer,
        );
      } else {
        await repo.updateItem(widget.existing!.id, {
          'name': _name.text.trim(),
          'description':
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'cost_points': cost,
          'stock': stock,
          'emoji': _emoji,
          'grade': schoolWide ? null : _grade,
          'class_num': schoolWide ? null : _classNum,
          'item_type': _isGroup ? 'group' : 'individual',
          'max_per_student': maxPer,
        });
      }
      ref.invalidate(allStoreItemsProvider);
      ref.invalidate(activeStoreItemsProvider);
      if (mounted) {
        if (widget.existing == null) {
          celebrateGrowth(context, ref, headline: '강화물 등록 완료! 🎁');
        }
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translateError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminTeacher ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? '새 강화물 추가' : '강화물 편집',
            style: GoogleFonts.notoSansKr(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.lg),

          // ── 아이콘 선택 ─────────────────────────────
          Text(
            '아이콘',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kStoreEmojis.map((e) {
              final selected = e == _emoji;
              return GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.teacherNavyLight
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.teacherNavy
                          : AppColors.borderLight,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSizes.md),

          // ── 판매 대상 ───────────────────────────────
          Text(
            '판매 대상',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (isAdmin)
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('🏫 전교 공통'),
                    selected: _schoolWide,
                    onSelected: (_) => setState(() => _schoolWide = true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('🧑‍🏫 특정 학급'),
                    selected: !_schoolWide,
                    onSelected: (_) => setState(() => _schoolWide = false),
                  ),
                ),
              ],
            )
          else
            Text(
              '우리 학급 학생에게만 보여요. (전교 공통 강화물은 관리자 선생님이 등록)',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          if (!isAdmin || !_schoolWide) ...[
            const SizedBox(height: AppSizes.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _grade,
                    decoration: const InputDecoration(
                      labelText: '학년',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var g = 1; g <= 6; g++)
                        DropdownMenuItem(value: g, child: Text('$g학년')),
                    ],
                    onChanged: (v) => setState(() => _grade = v ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _classNum,
                    decoration: const InputDecoration(
                      labelText: '반',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var c = 1; c <= 20; c++)
                        DropdownMenuItem(value: c, child: Text('$c반')),
                    ],
                    onChanged: (v) => setState(() => _classNum = v ?? 1),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSizes.md),

          PbsTextField(
            controller: _name,
            label: '강화물 이름',
            hint: '예: 빈츠 한 봉지',
          ),
          const SizedBox(height: AppSizes.md),
          PbsTextField(
            controller: _desc,
            label: '설명 (선택)',
            hint: '예: 인성생활부 비치',
          ),
          const SizedBox(height: AppSizes.md),
          // ── 강화물 유형 ──
          Text(
            '강화물 유형',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _TypeChip(
                  label: '개별',
                  desc: '한 명이 포인트를 내고 받아요',
                  selected: !_isGroup,
                  onTap: () => setState(() => _isGroup = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TypeChip(
                  label: '함께 키우기',
                  desc: '학급이 포인트를 모아 함께 받아요',
                  selected: _isGroup,
                  onTap: () => setState(() => _isGroup = true),
                ),
              ),
            ],
          ),
          if (_isGroup)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.studentGreenLight,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Text(
                  '과자 파티처럼 학급 전체가 함께 누리는 강화물에 알맞아요. '
                  '학생들이 조금씩 포인트를 보태 목표를 채우면 알림이 옵니다.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSizes.md),
          PbsTextField(
            controller: _cost,
            label: _isGroup ? '목표 포인트 (학급 합계)' : '필요 포인트',
            keyboardType: TextInputType.number,
            hint: _isGroup ? '예: 5000' : '예: 300',
          ),
          if (_isGroup) ...[
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '1인 최대 포인트 제한',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _capPerStudent,
                  onChanged: (v) => setState(() => _capPerStudent = v),
                ),
              ],
            ),
            if (_capPerStudent) ...[
              const SizedBox(height: AppSizes.sm),
              PbsTextField(
                controller: _maxPer,
                label: '한 사람이 보탤 수 있는 최대 포인트',
                keyboardType: TextInputType.number,
                hint: '예: 300',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '한 학생이 목표를 혼자 채우지 않도록 막아줍니다.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ],
          if (!_isGroup) ...[
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  '재고 무제한',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _unlimited,
                onChanged: (v) => setState(() => _unlimited = v),
              ),
            ],
          ),
          if (!_unlimited) ...[
            const SizedBox(height: AppSizes.sm),
            PbsTextField(
              controller: _stock,
              label: '재고 수량',
              keyboardType: TextInputType.number,
              hint: '예: 30',
            ),
          ],
          ],
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

/// 강화물 유형 선택 칩 (개별 / 함께 키우기)
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.teacherNavyLight : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.teacherNavy : AppColors.borderLight,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: selected
                      ? AppColors.teacherNavy
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? AppColors.teacherNavy
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              style: GoogleFonts.notoSansKr(
                fontSize: 10.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExchangesTab extends ConsumerWidget {
  const _ExchangesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingExchangesProvider);
    final all = ref.watch(allExchangesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pendingExchangesProvider);
        ref.invalidate(allExchangesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          const _ScopeNotice(),
          const SectionHeader(title: '🔔 처리 대기'),
          pending.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(translateError(e)),
            data: (list) {
              if (list.isEmpty) {
                return PbsCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '🎉 모두 처리되었어요',
                      style: GoogleFonts.notoSansKr(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: list.map((e) => _ExchangeTile(ex: e)).toList(),
              );
            },
          ),
          const SectionHeader(title: '📜 전체 내역'),
          all.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text(translateError(e)),
            data: (list) {
              final history =
                  list.where((e) => e.status != 'pending').toList();
              if (history.isEmpty) {
                return PbsCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 처리된 내역이 없어요.',
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary, fontSize: 12),
                    ),
                  ),
                );
              }
              return Column(
                children: history
                    .take(30)
                    .map((e) => _ExchangeTile(ex: e, readOnly: true))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: AppSizes.xxxl),
        ],
      ),
    );
  }
}

class _ExchangeTile extends ConsumerWidget {
  const _ExchangeTile({required this.ex, this.readOnly = false});
  final PointExchange ex;
  final bool readOnly;

  Color get _statusColor => switch (ex.status) {
        'pending' => AppColors.warning,
        'fulfilled' => AppColors.success,
        'cancelled' => AppColors.textTertiary,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.studentNickname ?? '학생',
                        style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (ex.classLabel != null)
                        Text(
                          ex.classLabel!,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ex.statusLabel,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${ex.itemName} · ${ex.costPoints}P',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              DateFormat('M/d HH:mm').format(ex.requestedAt),
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            if (!readOnly && ex.isPending) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(pointsRepositoryProvider)
                              .cancelExchange(ex.id);
                          ref.invalidate(pendingExchangesProvider);
                          ref.invalidate(allExchangesProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('취소했어요. 포인트는 환불됩니다.')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(translateError(e))),
                            );
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      child: const Text('취소·환불'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(pointsRepositoryProvider)
                              .fulfillExchange(ex.id);
                          ref.invalidate(pendingExchangesProvider);
                          ref.invalidate(allExchangesProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('수령 처리 완료!')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(translateError(e))),
                            );
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      child: const Text('수령 처리'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// 🔔 교환 요청 가시성 안내 — 담임은 본인이 등록한 강화물의 요청만 본다.
class _ScopeNotice extends ConsumerWidget {
  const _ScopeNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Text(isAdmin ? '👑' : '🧑‍🏫', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAdmin
                  ? '관리자는 우리 학교 전체 교환 요청을 볼 수 있어요.'
                  : '내가 등록한 강화물의 교환 요청만 보여요. 바로 지급 처리할 수 있어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🪙 포인트 경제 패널 (관리자) — 인플레이션을 눈으로 보고 조정한다.
/// 평균 잔액이 높을수록 강화물 가격을 올리거나 학기 마감을 검토한다.
class _EconomyPanel extends ConsumerWidget {
  const _EconomyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;
    // 관리자는 전교 현황, 담임 선생님은 우리 반 현황을 본다
    final stats = isAdmin
        ? ref.watch(pointEconomyProvider).value
        : ref.watch(classPointEconomyProvider).value;
    if (stats == null || stats['ok'] != true) return const SizedBox.shrink();
    final isClass = stats['scope'] == 'class';

    final avg = (stats['avg'] as num?)?.toInt() ?? 0;
    final median = (stats['median'] as num?)?.toInt() ?? 0;
    final maxP = (stats['max'] as num?)?.toInt() ?? 0;
    final richRatio = (stats['rich_ratio'] as num?)?.toInt() ?? 0;
    final f = NumberFormat('#,###');
    // 권장 가격대: 중앙값의 40~120% (한 학기에 2~3개 교환 가능한 수준)
    final lo = ((median * 0.4) / 50).round() * 50;
    final hi = ((median * 1.2) / 50).round() * 50;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.teacherNavyLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.teacherNavy.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    isClass ? '🪙 우리 반 포인트 현황' : '🪙 우리 학교 포인트 현황',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.teacherNavy)),
              ),
              if (isAdmin)
              GestureDetector(
                onTap: () => _showSeasonDialog(context, ref),
                child: Text('학기 마감 →',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.teacherNavy)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stat('평균 잔액', '${f.format(avg)}P'),
              _stat('중앙값', '${f.format(median)}P'),
              _stat('최고', '${f.format(maxP)}P'),
              _stat('1000P↑', '$richRatio%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            median <= 0
                ? '아직 쌓인 포인트가 적어요. 강화물은 100~300P부터 시작해보세요.'
                : '💡 권장 가격대 ${f.format(lo)}~${f.format(hi)}P '
                    '(한 학기에 2~3개 교환할 수 있는 수준)'
                    '${richRatio >= 30 ? "\n⚠️ 포인트가 많이 쌓였어요 — 가격을 올리거나 학기 마감을 검토해보세요." : ""}',
            style: GoogleFonts.notoSansKr(
                fontSize: 11.5, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.teacherNavy)),
            Text(label,
                style: GoogleFonts.notoSansKr(
                    fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ),
      );

  /// 학기 마감 — 전교생 잔여 포인트를 정산(소멸)하고 새 학기를 시작한다.
  void _showSeasonDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('학기 포인트 마감',
            style: GoogleFonts.notoSansKr(
                fontSize: 17, fontWeight: FontWeight.w900)),
        content: Text(
          '전교생의 남은 포인트를 0으로 정산하고 새 학기를 시작합니다.\n\n'
          '· 뱃지·명예의 전당·점검 기록은 그대로 유지돼요\n'
          '· 학생들에게 마감 안내 알림이 전송돼요\n'
          '· 되돌릴 수 없으니 학기말에만 사용해주세요',
          style: GoogleFonts.notoSansKr(
              fontSize: 13, height: 1.6, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소',
                  style:
                      GoogleFonts.notoSansKr(color: AppColors.textTertiary))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              final res = await SupabaseService.client
                  .rpc('close_point_season');
              final m = Map<String, dynamic>.from(res as Map);
              ref.invalidate(pointEconomyProvider);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(m['ok'] == true
                    ? '학기 마감 완료 — 학생 ${m['students']}명 · ${m['points']}P 정산'
                    : (m['error'] as String? ?? '실패했어요')),
              ));
            },
            child: Text('마감 실행',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
