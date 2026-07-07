import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../models/point_exchange.dart';
import '../models/point_store_item.dart';
import '../providers/points_provider.dart';

class StudentStoreScreen extends ConsumerWidget {
  const StudentStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(myPointsProvider);
    final itemsAsync = ref.watch(activeStoreItemsProvider);
    final myExchanges = ref.watch(myExchangesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myPointsProvider);
        ref.invalidate(activeStoreItemsProvider);
        ref.invalidate(myExchangesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl),
        children: [
          // Balance card
          _BalanceCard(balance: balance.value ?? 0),

          // Earn explanation
          const SizedBox(height: AppSizes.md),
          PbsCard(
            color: AppColors.studentGreenLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('💰', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '포인트 적립 방법',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800,
                        color: AppColors.studentGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '• 매일 자기점검 1회 = +100P\n• 월~금 모두 참여 보너스 = +500P',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          itemsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => PbsCard(
              child: Text(translateError(e),
                  style: GoogleFonts.notoSansKr(color: AppColors.danger)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Column(
                  children: [
                    const SectionHeader(title: '🛒 교환 가능 상품'),
                    PbsCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          '아직 등록된 상품이 없어요.\n담임선생님께 상점 등록을 요청해보세요!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              final classItems =
                  items.where((it) => it.isClassItem).toList();
              final schoolItems =
                  items.where((it) => !it.isClassItem).toList();
              Widget cards(List<PointStoreItem> list) => Column(
                    children: list
                        .map((it) => _ItemCard(
                              item: it,
                              balance: balance.value ?? 0,
                              onExchange: () =>
                                  _confirmExchange(context, ref, it),
                            ))
                        .toList(),
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (classItems.isNotEmpty) ...[
                    const SectionHeader(title: '🧑‍🏫 우리 반 상점'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '담임선생님이 우리 반을 위해 준비한 특별 상품이에요!',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppColors.studentGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    cards(classItems),
                  ],
                  if (schoolItems.isNotEmpty) ...[
                    const SectionHeader(title: '🏫 학교 상점'),
                    cards(schoolItems),
                  ],
                ],
              );
            },
          ),

          const SectionHeader(title: '📦 내 교환 내역'),
          myExchanges.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) {
                return PbsCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 교환 내역이 없어요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: list.take(10).map((e) => _ExchangeRow(ex: e)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExchange(
      BuildContext context, WidgetRef ref, PointStoreItem it) async {
    final balance = ref.read(myPointsProvider).value ?? 0;
    if (balance < it.costPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('포인트가 부족해요.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${it.name} 교환'),
        content: Text(
          '${it.costPoints}P가 차감됩니다.\n교환하시겠어요?\n\n'
          '${it.isClassItem ? "수령은 담임선생님께 받을 수 있어요." : "수령은 담당 선생님께 받을 수 있어요."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.studentGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('교환하기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(pointsRepositoryProvider).requestExchange(it.id);
      ref.invalidate(myPointsProvider);
      ref.invalidate(myExchangesProvider);
      ref.invalidate(activeStoreItemsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(it.isClassItem
              ? '교환 신청 완료! 담임선생님께 수령하세요.'
              : '교환 신청 완료! 담당 선생님께 수령하세요.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translateError(e))),
        );
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context) {
    return PbsCard(
      padding: const EdgeInsets.all(AppSizes.xl),
      color: AppColors.studentGreen,
      border: Border.all(color: AppColors.studentGreen),
      child: Row(
        children: [
          const Text('🪙', style: TextStyle(fontSize: 44)),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 포인트',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '${NumberFormat('#,###').format(balance)} P',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.balance,
    required this.onExchange,
  });

  final PointStoreItem item;
  final int balance;
  final VoidCallback onExchange;

  @override
  Widget build(BuildContext context) {
    final canAfford = balance >= item.costPoints;
    final soldOut = item.isSoldOut;
    final disabled = !canAfford || soldOut;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.studentGreenLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (item.description != null && item.description!.isNotEmpty)
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '${item.costPoints}P',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.studentGreen,
                        ),
                      ),
                      if (!item.isUnlimited) ...[
                        const SizedBox(width: 8),
                        Text(
                          '재고 ${item.stock}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: disabled ? null : onExchange,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.studentGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
                child: Text(
                  soldOut
                      ? '품절'
                      : !canAfford
                          ? '포인트 부족'
                          : '교환',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExchangeRow extends StatelessWidget {
  const _ExchangeRow({required this.ex});
  final PointExchange ex;

  Color get _statusColor => switch (ex.status) {
        'pending' => AppColors.warning,
        'fulfilled' => AppColors.success,
        'cancelled' => AppColors.textTertiary,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: PbsCard(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex.itemName,
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${DateFormat('MM/dd HH:mm').format(ex.requestedAt)} · ${ex.costPoints}P',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
      ),
    );
  }
}
