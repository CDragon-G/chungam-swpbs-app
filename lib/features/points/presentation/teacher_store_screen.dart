import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
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
    final canEdit = profile?.isAdminTeacher ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '포인트 상점',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: '상품 추가',
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
            Tab(text: '상품 관리'),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Text(
                  '아직 등록된 상품이 없어요.\n우측 상단 + 버튼으로 추가해주세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: items.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: _ItemRow(item: items[i]),
            ),
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
    return PbsCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.teacherNavyLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: const Text('🎁', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800,
                    color: item.isActive
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    decoration: item.isActive ? null : TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  '${item.costPoints}P · 재고 ${item.isUnlimited ? "무제한" : item.stock}',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showEditSheet(context, item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.danger),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('상품 삭제'),
                  content: Text(
                      '${item.name} 상품을 삭제하시겠어요?\n이미 교환된 기록은 그대로 유지됩니다.'),
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
          ),
        ],
      ),
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

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  bool _unlimited = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _cost = TextEditingController(text: e?.costPoints.toString() ?? '');
    _stock = TextEditingController(text: e?.stock?.toString() ?? '');
    _unlimited = e?.stock == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _cost.dispose();
    _stock.dispose();
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
    final stock = _unlimited ? null : int.tryParse(_stock.text);
    if (!_unlimited && (stock == null || stock < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재고는 0 이상의 숫자여야 해요.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(pointsRepositoryProvider);
      final profile = ref.read(profileProvider).value;
      if (profile?.schoolId == null) return;

      if (widget.existing == null) {
        final existing =
            ref.read(allStoreItemsProvider).value ?? const <PointStoreItem>[];
        await repo.createItem(
          schoolId: profile!.schoolId!,
          name: _name.text.trim(),
          description:
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          costPoints: cost,
          stock: stock,
          orderIndex: existing.length,
        );
      } else {
        await repo.updateItem(widget.existing!.id, {
          'name': _name.text.trim(),
          'description':
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'cost_points': cost,
          'stock': stock,
        });
      }
      ref.invalidate(allStoreItemsProvider);
      ref.invalidate(activeStoreItemsProvider);
      if (mounted) Navigator.pop(context);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? '새 상품 추가' : '상품 편집',
            style: GoogleFonts.notoSansKr(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          PbsTextField(
            controller: _name,
            label: '상품명',
            hint: '예: 빈츠 한 봉지',
          ),
          const SizedBox(height: AppSizes.md),
          PbsTextField(
            controller: _desc,
            label: '설명 (선택)',
            hint: '예: 인성생활부 비치',
          ),
          const SizedBox(height: AppSizes.md),
          PbsTextField(
            controller: _cost,
            label: '필요 포인트',
            keyboardType: TextInputType.number,
            hint: '예: 300',
          ),
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
