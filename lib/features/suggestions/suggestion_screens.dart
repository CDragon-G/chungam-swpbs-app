import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/widgets/pbs_card.dart';
import 'suggestions_repository.dart';

final suggestionsRepositoryProvider =
    Provider((_) => SuggestionsRepository());

final mySuggestionsProvider = FutureProvider<List<RuleSuggestion>>(
    (ref) => ref.read(suggestionsRepositoryProvider).mine());

final allSuggestionsProvider = FutureProvider<List<RuleSuggestion>>(
    (ref) => ref.read(suggestionsRepositoryProvider).list());

// ══════════════════ 학생 화면 ══════════════════

/// 💌 규칙 건의함 — 학생이 규칙에 대해 하고 싶은 말을 보낸다.
/// 내용은 관리자 선생님만 읽는다. 다른 학생에게는 보이지 않는다.
class SuggestionBoxScreen extends ConsumerStatefulWidget {
  const SuggestionBoxScreen({super.key});

  @override
  ConsumerState<SuggestionBoxScreen> createState() => _State();
}

class _State extends ConsumerState<SuggestionBoxScreen> {
  final _body = TextEditingController();
  String? _space;
  bool _sending = false;

  static const _spaces = ['수업', '복도', '급식실', '화장실', '운동장', '기타'];

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('5글자 이상 적어주세요.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(suggestionsRepositoryProvider)
          .submit(body: text, space: _space);
      _body.clear();
      setState(() => _space = null);
      ref.invalidate(mySuggestionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('건의를 보냈어요. 선생님이 읽어보실 거예요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(mySuggestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💌 규칙 건의함',
                style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('선생님께만 전달돼요',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          PbsCard(
            color: AppColors.studentGreenLight,
            child: Text(
              '우리 학교 규칙에 대해 하고 싶은 말을 적어주세요.\n'
              '고쳤으면 하는 규칙, 새로 있었으면 하는 규칙 모두 좋아요.\n\n'
              '보낸 내용은 관리자 선생님만 보실 수 있어요.\n'
              '다른 친구들에게는 보이지 않아요.',
              style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.65),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text('어디에 대한 건의인가요? (선택)',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final s in _spaces)
                ChoiceChip(
                  label: Text(s,
                      style: GoogleFonts.notoSansKr(fontSize: 12.5)),
                  selected: _space == s,
                  selectedColor:
                      AppColors.studentGreen.withValues(alpha: 0.18),
                  onSelected: (on) => setState(() => _space = on ? s : null),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _body,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: '예) 복도에서 뛰지 않기 규칙은 좋은데,\n'
                  '쉬는 시간이 짧아서 지키기 어려워요.',
              border: OutlineInputBorder(),
            ),
          ),
          PbsPrimaryButton(
            label: '건의 보내기',
            color: AppColors.studentGreen,
            loading: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 6),
          Text('하루에 3개까지 보낼 수 있어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5, color: AppColors.textTertiary)),
          const SectionHeader(title: '📮 내가 보낸 건의'),
          mine.when(
            loading: () => const PbsCard(child: SizedBox(height: 40)),
            error: (e, _) => PbsCard(child: Text(translateError(e))),
            data: (items) {
              if (items.isEmpty) {
                return PbsCard(
                  child: Text('아직 보낸 건의가 없어요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, color: AppColors.textTertiary)),
                );
              }
              return Column(
                children: items
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: PbsCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (s.space != null)
                                      _Chip(text: s.space!),
                                    const Spacer(),
                                    _Chip(
                                        text: s.statusLabel,
                                        color: s.status == 'accepted'
                                            ? AppColors.success
                                            : AppColors.textTertiary),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(s.body,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 13, height: 1.55)),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('M/d HH:mm')
                                      .format(s.createdAt.toLocal()),
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ))
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

// ══════════════════ 관리자 화면 ══════════════════

/// 📬 건의함 관리 — 관리자 선생님만 들어온다.
class SuggestionAdminScreen extends ConsumerWidget {
  const SuggestionAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSuggestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('📬 규칙 건의함',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(allSuggestionsProvider),
        child: all.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(translateError(e))),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(AppSizes.lg),
                children: [
                  PbsCard(
                    child: Text(
                      '아직 들어온 건의가 없어요.\n'
                      '학생 화면 [규칙 건의함]에서 보낼 수 있어요.',
                      style:
                          GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
                    ),
                  ),
                ],
              );
            }
            final fresh = items.where((s) => s.status == 'new').length;
            return ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                if (fresh > 0)
                  PbsCard(
                    color: AppColors.teacherNavyLight,
                    child: Text('아직 읽지 않은 건의가 $fresh건 있어요.',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.teacherNavy)),
                  ),
                const SizedBox(height: AppSizes.sm),
                ...items.map((s) => _AdminTile(s: s)),
                const SizedBox(height: AppSizes.xxxl),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminTile extends ConsumerWidget {
  const _AdminTile({required this.s});
  final RuleSuggestion s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> set(String status) async {
      try {
        await ref
            .read(suggestionsRepositoryProvider)
            .setStatus(s.id, status);
        ref.invalidate(allSuggestionsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(translateError(e))));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PbsCard(
        color: s.status == 'new' ? AppColors.surface : AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.who,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
                if (s.space != null) _Chip(text: s.space!),
                const SizedBox(width: 4),
                _Chip(
                    text: s.statusLabel,
                    color: switch (s.status) {
                      'new' => AppColors.warning,
                      'accepted' => AppColors.success,
                      'declined' => AppColors.textTertiary,
                      _ => AppColors.textSecondary,
                    }),
              ],
            ),
            const SizedBox(height: 8),
            Text(s.body,
                style: GoogleFonts.notoSansKr(fontSize: 13.5, height: 1.6)),
            const SizedBox(height: 6),
            Text(DateFormat('M/d HH:mm').format(s.createdAt.toLocal()),
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (s.status == 'new')
                  TextButton(
                      onPressed: () => set('read'),
                      child: Text('확인함',
                          style: GoogleFonts.notoSansKr(fontSize: 12.5))),
                TextButton(
                    onPressed: () => set('accepted'),
                    child: Text('반영하기',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5,
                            color: AppColors.success,
                            fontWeight: FontWeight.w800))),
                TextButton(
                    onPressed: () => set('declined'),
                    child: Text('보류',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, color: AppColors.textTertiary))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: GoogleFonts.notoSansKr(
              fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    );
  }
}
