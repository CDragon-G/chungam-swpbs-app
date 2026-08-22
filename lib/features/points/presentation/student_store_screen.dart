import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../../student/providers/badge_provider.dart';
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
                          '아직 등록된 강화물이 없어요.\n담임선생님께 교환소 등록을 요청해보세요!',
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
              final groupItems = items.where((it) => it.isGroup).toList();
              final solo = items.where((it) => !it.isGroup).toList();
              final classItems = solo.where((it) => it.isClassItem).toList();
              final schoolItems = solo.where((it) => !it.isClassItem).toList();
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
                  if (groupItems.isNotEmpty) ...[
                    const SectionHeader(title: '🌱 함께 키우기'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '우리 반이 포인트를 모아 함께 받는 강화물이에요. 조금씩 보태면 목표가 채워져요!',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppColors.studentGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...groupItems.map((it) => _GroupCard(item: it)),
                  ],
                  if (classItems.isNotEmpty) ...[
                    const SectionHeader(title: '🧑‍🏫 우리 반 교환소'),
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
                    const SectionHeader(title: '🏫 학교 교환소'),
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
      // 수확 뱃지(첫 수확·수확왕) 평가
      await evaluateAndAwardBadges(ref);
      if (context.mounted) {
        celebrateGrowth(context, ref,
            headline: it.isClassItem
                ? '교환 신청 완료! 담임선생님께 수령하세요 🎁'
                : '교환 신청 완료! 담당 선생님께 수령하세요 🎁');
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

/// 🌱 함께 키우기 카드 — 목표 진행률과 기여 TOP 3를 보여주고 포인트를 보탠다.
class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.item});
  final PointStoreItem item;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  GroupItemStatus? _st;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st =
          await ref.read(pointsRepositoryProvider).groupStatus(widget.item.id);
      if (!mounted) return;
      setState(() {
        _st = st;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final st = _st;
    final balance = ref.watch(myPointsProvider).value ?? 0;
    final done = st?.achieved ?? false;

    return PbsCard(
      color: done ? AppColors.studentGreenLight : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(it.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      done
                          ? '목표 달성! 곧 받을 수 있어요'
                          : '${it.scopeLabel} · 함께 키우는 중',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11.5,
                        color: done
                            ? AppColors.studentGreen
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (done)
                const Icon(Icons.verified_rounded,
                    color: AppColors.studentGreen, size: 26),
            ],
          ),
          if (it.description != null && it.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              it.description!,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator(minHeight: 10)
          else if (st != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: st.progress,
                minHeight: 12,
                backgroundColor: AppColors.borderLight,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.studentGreen),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${st.raised}P / ${st.goal}P',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.studentGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${st.percent}%',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${st.people}명 참여',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (st.top.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏅 많이 보탠 친구',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ...List.generate(st.top.length, (i) {
                      const medals = ['🥇', '🥈', '🥉'];
                      final c = st.top[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Text(medals[i],
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                c.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${c.amount}P',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.studentGreen,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (st.myAmount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  st.maxPerStudent == null
                      ? '내가 보탠 포인트 ${st.myAmount}P'
                      : '내가 보탠 포인트 ${st.myAmount}P · 한 사람 최대 ${st.maxPerStudent}P',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.studentGreen,
                  disabledBackgroundColor: AppColors.borderLight,
                ),
                onPressed: (done || st.myMaxAddable(balance) <= 0)
                    ? null
                    : () => _contribute(st, balance),
                child: Text(
                  done
                      ? '목표를 채웠어요 🎉'
                      : st.myMaxAddable(balance) <= 0
                          ? (balance <= 0 ? '포인트가 부족해요' : '더 보탤 수 없어요')
                          : '포인트 보태기',
                  style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _contribute(GroupItemStatus st, int balance) async {
    final maxAdd = st.myMaxAddable(balance);
    var amount = maxAdd >= 100 ? 100 : maxAdd;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) => AlertDialog(
          title: Text('포인트 보태기',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.item.name}\n목표까지 ${st.remain}P 남았어요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Text(
                '$amount P',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.studentGreen,
                ),
              ),
              Slider(
                value: amount.toDouble(),
                min: 0,
                max: maxAdd.toDouble(),
                divisions: maxAdd >= 10 ? (maxAdd ~/ 10) : null,
                activeColor: AppColors.studentGreen,
                onChanged: (v) => setSt(() => amount = v.round()),
              ),
              Text(
                '보유 ${balance}P · 최대 ${maxAdd}P까지 보탤 수 있어요',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('취소',
                  style:
                      GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.studentGreen),
              onPressed:
                  amount <= 0 ? null : () => Navigator.pop(dialogCtx, true),
              child: Text('보태기',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || amount <= 0) return;

    try {
      final next = await ref
          .read(pointsRepositoryProvider)
          .contribute(itemId: widget.item.id, amount: amount);
      ref.invalidate(myPointsProvider);
      ref.invalidate(activeStoreItemsProvider);
      if (!mounted) return;
      setState(() => _st = next);
      celebrateGrowth(context, ref,
          headline: next.achieved
              ? '목표 달성! 우리 반이 함께 해냈어요 🎉'
              : '${amount}P를 보탰어요! 목표까지 ${next.remain}P 🌱');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translateError(e))),
      );
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  if (item.isClassItem && item.createdByName != null)
                    Text(
                      '🧑‍🏫 ${item.createdByName} 선생님',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.studentGreen,
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
