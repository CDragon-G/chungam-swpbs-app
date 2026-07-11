import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../../school/providers/school_provider.dart';
import '../data/vote_repository.dart';
import 'vote_hint_card.dart';
import '../models/vote_models.dart';
import '../providers/vote_provider.dart';

/// 🍽️ 수업맛집 — 우리 학교 수업 규칙을 잘 지킨 학급을 교사들이 매주 투표.
/// (규칙 이름은 학교마다 달라요 — 라운드 개설은 '수업' 규칙이 있어야 가능)
class ClassVoteScreen extends ConsumerStatefulWidget {
  const ClassVoteScreen({super.key});

  @override
  ConsumerState<ClassVoteScreen> createState() => _ClassVoteScreenState();
}

class _ClassVoteScreenState extends ConsumerState<ClassVoteScreen> {
  String? _subject;
  int _grade = 1;
  int _classNum = 1;
  bool _voting = false;

  void _refreshAll() {
    ref.invalidate(voteRoundsProvider);
    ref.invalidate(voteSubjectsProvider);
    ref.invalidate(voteHintProvider);
    final round = ref.read(openRoundProvider);
    if (round != null) {
      ref.invalidate(myVotesProvider(round.id));
      ref.invalidate(voteTallyProvider(round.id));
    }
  }

  Future<void> _castVote(VoteRound round) async {
    final subject = _subject;
    if (subject == null || subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('과목을 먼저 선택해주세요.')),
      );
      return;
    }
    setState(() => _voting = true);
    try {
      await ref.read(voteRepositoryProvider).castVote(
            roundId: round.id,
            subject: subject,
            grade: _grade,
            classNum: _classNum,
          );
      ref.invalidate(myVotesProvider(round.id));
      ref.invalidate(voteTallyProvider(round.id));
      ref.invalidate(voteHintProvider);
      if (mounted) {
        celebrateGrowth(context, ref,
            headline: '🍽️ $_grade학년 $_classNum반에 투표했어요!');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translateError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminTeacher ?? false;
    final roundsAsync = ref.watch(voteRoundsProvider);
    final openRound = ref.watch(openRoundProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🍽️ 수업맛집',
                style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('수업 규칙을 잘 지킨 학급 투표',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: '과목 관리',
              icon: const Icon(Icons.menu_book_rounded,
                  color: AppColors.teacherNavy),
              onPressed: () => _showSubjectManager(context),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: roundsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(translateError(e))),
          data: (rounds) {
            final closed = rounds.where((r) => !r.isOpen).toList();
            return ListView(
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                if (openRound == null) ...[
                  PbsCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          const Text('🍽️', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text('진행 중인 투표가 없어요.',
                              style: GoogleFonts.notoSansKr(
                                  fontWeight: FontWeight.w800)),
                          Text(
                            isAdmin
                                ? '아래 버튼으로 새 투표를 시작하세요.'
                                : '관리자 선생님이 투표를 시작하면 여기에 표시돼요.',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 12, color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: AppSizes.md),
                    PbsPrimaryButton(
                      label: '🗳️ 새 투표 시작',
                      color: AppColors.teacherNavy,
                      onPressed: () => _showCreateRound(context),
                    ),
                  ],
                ] else ...[
                  _RoundHeader(round: openRound),
                  const SizedBox(height: AppSizes.md),
                  const VoteHintCard(),
                  _buildVoteForm(openRound),
                  const SectionHeader(title: '🗳️ 이번 주 내 투표'),
                  _MyWeekVotes(round: openRound),
                  if (isAdmin) ...[
                    const SectionHeader(title: '📊 실시간 집계 (관리자만 보여요)'),
                    _TallyView(roundId: openRound.id),
                    const SizedBox(height: AppSizes.md),
                    OutlinedButton.icon(
                      onPressed: () => _confirmClose(openRound),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: Text('투표 마감 · 결과 공개',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
                if (closed.isNotEmpty) ...[
                  const SectionHeader(title: '🏆 지난 투표 결과'),
                  ...closed.take(3).map((r) => _ClosedRoundCard(round: r)),
                ],
                const SizedBox(height: AppSizes.xxxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVoteForm(VoteRound round) {
    final subjectsAsync = ref.watch(voteSubjectsProvider);
    final myVotesAsync = ref.watch(myVotesProvider(round.id));
    final weekKey = VoteRepository.currentWeekKey();
    final usedThisWeek = (myVotesAsync.value ?? [])
        .where((v) => v.weekKey == weekKey)
        .length;
    final remaining = (round.votesPerWeek - usedThisWeek).clamp(0, 99);

    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('이번 주 남은 투표권',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: remaining > 0
                      ? AppColors.studentGreenLight
                      : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$remaining / ${round.votesPerWeek}표',
                  style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w900,
                    color: remaining > 0
                        ? AppColors.studentGreen
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          subjectsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(translateError(e)),
            data: (subjects) {
              if (subjects.isEmpty) {
                return Text(
                  '등록된 과목이 없어요. 관리자 선생님이 우측 상단 📖 버튼으로 과목을 추가하면 투표할 수 있어요.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, color: AppColors.textTertiary),
                );
              }
              return DropdownButtonFormField<String>(
                value: subjects.any((s) => s.name == _subject) ? _subject : null,
                decoration: const InputDecoration(
                  labelText: '내 과목',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in subjects)
                    DropdownMenuItem(value: s.name, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _subject = v),
              );
            },
          ),
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
          const SizedBox(height: AppSizes.md),
          PbsPrimaryButton(
            label: remaining > 0 ? '🍽️ 투표하기' : '이번 주 투표 완료!',
            color: AppColors.teacherNavy,
            loading: _voting,
            onPressed: remaining > 0 ? () => _castVote(round) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(VoteRound round) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('투표 마감',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '"${round.title}" 투표를 마감할까요?\n\n'
          '마감하면 더 이상 투표할 수 없고,\n'
          '집계 결과가 모든 선생님에게 공개돼요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('마감하기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(voteRepositoryProvider).closeRound(round.id);
      _refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  Future<void> _showCreateRound(BuildContext context) async {
    // 개설 전제: '수업' 규칙이 설정돼 있어야 함 (서버 트리거로도 강제)
    final profile = ref.read(profileProvider).value;
    final schoolId = profile?.schoolId;
    if (schoolId == null) return;
    try {
      final rules =
          await ref.read(schoolRepositoryProvider).fetchRules(schoolId);
      final hasClassRules = rules.any((r) => r.space == '수업');
      if (!hasClassRules) {
        if (!mounted) return;
        await showDialog<void>(
          context: this.context,
          builder: (ctx) => AlertDialog(
            title: Text('수업 규칙을 먼저 설정해주세요',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
            content: Text(
              '수업맛집은 우리 학교의 수업 규칙을 기준으로\n'
              '가장 잘 실천한 학급에 투표하는 프로그램이에요.\n\n'
              '하단 [규칙] 탭에서 \'수업\' 공간의 규칙을\n'
              '먼저 만든 뒤 투표를 시작할 수 있어요.',
              style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (_) {/* 조회 실패 시 서버 트리거가 최종 방어 */}
    if (!mounted) return;

    final title = TextEditingController();
    var votes = 2;
    var weeks = 5;
    await showDialog<void>(
      context: this.context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('새 투표 시작',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: '투표 이름',
                  hintText: '예: 2026-2학기 중간고사 전',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('교사 1인당 주간 투표권',
                        style: GoogleFonts.notoSansKr(fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: votes > 1 ? () => setSt(() => votes--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$votes표',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  IconButton(
                    onPressed: votes < 10 ? () => setSt(() => votes++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('총 진행 주차',
                        style: GoogleFonts.notoSansKr(fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: weeks > 1 ? () => setSt(() => weeks--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$weeks주',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  IconButton(
                    onPressed: weeks < 20 ? () => setSt(() => weeks++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                try {
                  await ref.read(voteRepositoryProvider).createRound(
                        schoolId: schoolId,
                        title: title.text,
                        votesPerWeek: votes,
                        totalWeeks: weeks,
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refreshAll();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(translateError(e))));
                  }
                }
              },
              child: const Text('시작'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubjectManager(BuildContext context) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Consumer(
          builder: (ctx, ref2, _) {
            final subjects = ref2.watch(voteSubjectsProvider).value ?? [];
            return Padding(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('📖 과목 관리',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('우리 학교에서 투표에 사용할 과목 목록이에요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary)),
                  const SizedBox(height: AppSizes.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: subjects
                        .map((s) => Chip(
                              label: Text(s.name,
                                  style:
                                      GoogleFonts.notoSansKr(fontSize: 13)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () async {
                                await ref2
                                    .read(voteRepositoryProvider)
                                    .deleteSubject(s.id);
                                ref2.invalidate(voteSubjectsProvider);
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: '과목 추가',
                            hintText: '예: 국어',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) return;
                          final profile = ref2.read(profileProvider).value;
                          if (profile?.schoolId == null) return;
                          try {
                            await ref2.read(voteRepositoryProvider).addSubject(
                                profile!.schoolId!, name, subjects.length);
                            controller.clear();
                            ref2.invalidate(voteSubjectsProvider);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content: Text(translateError(e))));
                            }
                          }
                        },
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.round});
  final VoteRound round;

  /// 시작일 기준 현재 몇 주차인지 (KST, 서버 vote_hint와 동일 규칙).
  static int _weekNow(VoteRound round) {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final kstStart = round.createdAt.toUtc().add(const Duration(hours: 9));
    final days = DateTime(kstNow.year, kstNow.month, kstNow.day)
        .difference(DateTime(kstStart.year, kstStart.month, kstStart.day))
        .inDays;
    return ((days ~/ 7) + 1).clamp(1, round.totalWeeks);
  }

  @override
  Widget build(BuildContext context) {
    return PbsCard(
      color: AppColors.teacherNavy,
      border: Border.all(color: AppColors.teacherNavy),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(round.title,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '📅 ${_weekNow(round)}/${round.totalWeeks}주차',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '매주 우리 학교 수업 규칙을 가장 잘 실천한 학급에 투표해주세요. '
            '교사 1인당 주 ${round.votesPerWeek}표, 매주 새로 투표할 수 있어요.',
            style: GoogleFonts.notoSansKr(
                fontSize: 12, color: Colors.white70, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _MyWeekVotes extends ConsumerWidget {
  const _MyWeekVotes({required this.round});
  final VoteRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votesAsync = ref.watch(myVotesProvider(round.id));
    final weekKey = VoteRepository.currentWeekKey();
    return votesAsync.when(
      loading: () => const PbsCard(child: SizedBox(height: 40)),
      error: (e, _) => PbsCard(child: Text(translateError(e))),
      data: (votes) {
        final thisWeek = votes.where((v) => v.weekKey == weekKey).toList();
        if (thisWeek.isEmpty) {
          return PbsCard(
            child: Text(
              '아직 이번 주 투표를 하지 않았어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13, color: AppColors.textTertiary),
            ),
          );
        }
        return Column(
          children: thisWeek
              .map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: PbsCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md, vertical: AppSizes.sm),
                      child: Row(
                        children: [
                          const Text('🍽️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.classLabel,
                                    style: GoogleFonts.notoSansKr(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                                Text(
                                  '${v.subject} · ${DateFormat('M/d HH:mm').format(v.createdAt.toLocal())}',
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '투표 취소',
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: AppColors.textTertiary),
                            onPressed: () async {
                              await ref
                                  .read(voteRepositoryProvider)
                                  .deleteVote(v.id);
                              ref.invalidate(myVotesProvider(round.id));
                              ref.invalidate(voteTallyProvider(round.id));
                            },
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

/// 집계 표시 — 학년별로 묶어 득표순, 1위 강조.
class _TallyView extends ConsumerWidget {
  const _TallyView({required this.roundId});
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tallyAsync = ref.watch(voteTallyProvider(roundId));
    return tallyAsync.when(
      loading: () => const PbsCard(child: SizedBox(height: 60)),
      error: (e, _) => PbsCard(child: Text(translateError(e))),
      data: (rows) {
        if (rows.isEmpty) {
          return PbsCard(
            child: Text('아직 투표가 없어요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, color: AppColors.textTertiary)),
          );
        }
        final byGrade = <int, List<VoteTallyRow>>{};
        for (final r in rows) {
          byGrade.putIfAbsent(r.grade, () => []).add(r);
        }
        final grades = byGrade.keys.toList()..sort();
        return Column(
          children: grades.map((g) {
            final list = byGrade[g]!;
            final max = list.first.votes;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: PbsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$g학년',
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w900,
                            color: AppColors.teacherNavy)),
                    const SizedBox(height: 6),
                    ...list.take(5).map((r) {
                      final isTop = r.votes == max;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${isTop ? "🏆 " : ""}${r.classNum}반',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  fontWeight: isTop
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: AppColors.borderLight,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor:
                                        (r.votes / max).clamp(0.05, 1.0),
                                    child: Container(
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: isTop
                                            ? AppColors.studentGreen
                                            : AppColors.teacherNavy
                                                .withValues(alpha: 0.45),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${r.votes}표',
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// 마감된 라운드 — 학년별 1위(수업맛집) 표시.
class _ClosedRoundCard extends ConsumerWidget {
  const _ClosedRoundCard({required this.round});
  final VoteRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tallyAsync = ref.watch(voteTallyProvider(round.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        color: const Color(0xFFFEF9E7),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(round.title,
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w900, fontSize: 15)),
            if (round.closedAt != null)
              Text(
                '${DateFormat('yyyy.M.d').format(round.closedAt!.toLocal())} 마감',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            const SizedBox(height: 8),
            tallyAsync.when(
              loading: () => const SizedBox(
                  height: 30, child: Center(child: LinearProgressIndicator())),
              error: (e, _) => Text(translateError(e),
                  style: GoogleFonts.notoSansKr(fontSize: 12)),
              data: (rows) {
                if (rows.isEmpty) {
                  return Text('투표 기록이 없어요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary));
                }
                final byGrade = <int, VoteTallyRow>{};
                for (final r in rows) {
                  // rows는 학년별 득표순 정렬 → 첫 항목이 1위
                  byGrade.putIfAbsent(r.grade, () => r);
                }
                final grades = byGrade.keys.toList()..sort();
                return Column(
                  children: grades
                      .map((g) => Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Text('🏆',
                                    style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(
                                  '${byGrade[g]!.classLabel} (${byGrade[g]!.votes}표)',
                                  style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: const Color(0xFFB45309)),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
