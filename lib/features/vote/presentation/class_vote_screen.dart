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
    ref.invalidate(voteBlackoutsProvider);
    final round = ref.read(openRoundProvider);
    if (round != null) {
      ref.invalidate(myVotesProvider(round.id));
      ref.invalidate(voteTallyProvider(round.id));
      ref.invalidate(voteProgressProvider(round.id));
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
      ref.invalidate(voteProgressProvider(round.id));
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
              tooltip: '학년별 일정',
              icon: const Icon(Icons.event_busy_rounded,
                  color: AppColors.teacherNavy),
              onPressed: () => _showGradeScheduleSheet(context),
            ),
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
                  // 먼저 마감된 학년(예: 3학년)의 결과는 모든 선생님께 공개
                  if (!isAdmin) _EarlyClosedResults(round: openRound),
                  if (isAdmin) ...[
                    const SectionHeader(title: '📊 실시간 집계 (관리자만 보여요)'),
                    _TallyView(roundId: openRound.id),
                    const SizedBox(height: AppSizes.md),
                    PbsPrimaryButton(
                      label: '📢 투표 안내 보내기',
                      color: AppColors.teacherNavy,
                      onPressed: () => _confirmSendNotice(openRound),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    OutlinedButton.icon(
                      onPressed: () => _showEditRound(openRound),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.teacherNavy,
                        side: const BorderSide(color: AppColors.teacherNavy),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                      label: Text('투표 수정 · 투표 가능한 날 지정',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    OutlinedButton.icon(
                      onPressed: () => _showGradeScheduleSheet(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.teacherNavy,
                        side: const BorderSide(color: AppColors.teacherNavy),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.event_busy_rounded, size: 18),
                      label: Text('학년별 일정 · 시험 기간 · 조기 마감',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: AppSizes.sm),
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

    // 학년마다 시험 일정이 달라, 지금 투표를 받을 수 있는 학년만 고를 수 있다.
    final prog = ref.watch(voteProgressProvider(round.id)).value ??
        VoteProgress.empty;
    final progress = prog.grades;
    final gradeItems = progress.isEmpty
        // 아직 현황을 못 받았으면 예전처럼 전 학년을 보여준다.
        ? [for (var g = 1; g <= 6; g++) g]
        : progress.where((p) => p.isVotable).map((p) => p.grade).toList();
    final blocked = progress.where((p) => !p.isVotable).toList();
    // 학기 시작 때 지정한 투표 기간·요일에 맞지 않는 날이면 오늘은 투표할 수 없다.
    final dayOk = prog.todayOk;
    final gradeOk = dayOk && gradeItems.contains(_grade);

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
          if (!dayOk && prog.todayReason != null) ...[
            const SizedBox(height: AppSizes.sm),
            _NoticeBox(text: prog.todayReason!),
          ],
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: AppSizes.sm),
            _PausedGradesNotice(blocked: blocked),
          ],
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: gradeOk ? _grade : null,
                  decoration: const InputDecoration(
                    labelText: '학년',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  hint: Text(gradeItems.isEmpty ? '투표 가능한 학년 없음' : '선택',
                      style: GoogleFonts.notoSansKr(fontSize: 13)),
                  items: [
                    for (final g in gradeItems)
                      DropdownMenuItem(value: g, child: Text('$g학년')),
                  ],
                  onChanged: gradeItems.isEmpty
                      ? null
                      : (v) => setState(() => _grade = v ?? _grade),
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
            label: !dayOk
                ? '오늘은 투표할 수 없어요'
                : gradeItems.isEmpty
                    ? '지금은 모든 학년이 쉬는 기간이에요'
                    : !gradeOk
                        ? '학년을 선택해주세요'
                        : remaining > 0
                            ? '🍽️ 투표하기'
                            : '이번 주 투표 완료!',
            color: AppColors.teacherNavy,
            loading: _voting,
            onPressed:
                remaining > 0 && gradeOk ? () => _castVote(round) : null,
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

  // ── 학년별 투표 일정 (관리자) ─────────────────────────────
  //   3학년은 진학 때문에 시험을 먼저 본다. 시험 주간에는 볼 수업이 없으니
  //   그 학년만 투표를 쉬게 하고, 쉰 주는 주차에서 빼고, 먼저 마감할 수 있게 한다.
  Future<void> _showGradeScheduleSheet(BuildContext context) async {
    final schoolId = ref.read(profileProvider).value?.schoolId;
    if (schoolId == null) return;

    await showModalBottomSheet<void>(
      context: this.context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Consumer(
          builder: (ctx, r, __) {
            final round = r.watch(openRoundProvider);
            final blackoutsAsync = r.watch(voteBlackoutsProvider);
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(AppSizes.lg),
              children: [
                Row(
                  children: [
                    const Text('🗓️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('학년별 투표 일정',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                Text(
                  '3학년처럼 시험을 먼저 보는 학년은 그 기간 동안 투표를 쉽니다. '
                  '쉬는 주는 그 학년의 주차에 포함되지 않고, '
                  '먼저 끝난 학년은 따로 마감해서 결과를 발표할 수 있어요.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.textSecondary),
                ),
                if (round == null) ...[
                  const SizedBox(height: AppSizes.md),
                  PbsCard(
                    child: Text(
                      '진행 중인 투표가 없어요.\n'
                      '투표를 시작하면 학년별 주차와 마감을 여기서 조절할 수 있어요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          height: 1.6,
                          color: AppColors.textTertiary),
                    ),
                  ),
                ] else ...[
                  const SectionHeader(title: '📈 학년별 진행'),
                  r.watch(voteProgressProvider(round.id)).when(
                        loading: () =>
                            const PbsCard(child: SizedBox(height: 60)),
                        error: (e, _) => PbsCard(child: Text(translateError(e))),
                        data: (prog) => Column(
                          children: prog.grades
                              .map((p) => _GradeScheduleRow(round: round, p: p))
                              .toList(),
                        ),
                      ),
                ],
                const SectionHeader(title: '⏸ 투표 쉬는 기간'),
                blackoutsAsync.when(
                  loading: () => const PbsCard(child: SizedBox(height: 50)),
                  error: (e, _) => PbsCard(child: Text(translateError(e))),
                  data: (list) {
                    if (list.isEmpty) {
                      return PbsCard(
                        child: Text(
                          '등록된 기간이 없어요.\n'
                          '학년별 시험 기간을 넣어두면 그 학년은 자동으로 투표를 쉽니다.',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5,
                              height: 1.6,
                              color: AppColors.textTertiary),
                        ),
                      );
                    }
                    return Column(
                      children: list
                          .map((b) => _BlackoutTile(blackout: b))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: AppSizes.md),
                PbsPrimaryButton(
                  label: '＋ 쉬는 기간 추가',
                  color: AppColors.teacherNavy,
                  onPressed: () => _showAddBlackout(sheetCtx, schoolId),
                ),
                const SizedBox(height: AppSizes.xxxl),
              ],
            );
          },
        ),
      ),
    );
    _refreshAll();
  }

  Future<void> _showAddBlackout(
      BuildContext sheetCtx, String schoolId) async {
    final grades = ref.read(schoolGradesProvider).value ?? const [1, 2, 3];
    final labelCtrl = TextEditingController(text: '중간고사');
    int? grade = grades.isEmpty ? null : grades.last; // 보통 3학년이 먼저 본다
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 3));

    final saved = await showDialog<bool>(
      context: sheetCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) {
          Future<void> pick(bool isStart) async {
            final base = isStart ? start : end;
            final picked = await showDatePicker(
              context: dialogCtx,
              initialDate: base,
              firstDate: DateTime(base.year - 1),
              lastDate: DateTime(base.year + 2),
            );
            if (picked == null) return;
            setSt(() {
              if (isStart) {
                start = picked;
                if (end.isBefore(start)) end = start;
              } else {
                end = picked.isBefore(start) ? start : picked;
              }
            });
          }

          return AlertDialog(
            title: Text('투표 쉬는 기간',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: '이름',
                      hintText: '예: 2학기 중간고사',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: ['중간고사', '기말고사', '수학여행', '체험학습']
                        .map((s) => ActionChip(
                              label: Text(s,
                                  style:
                                      GoogleFonts.notoSansKr(fontSize: 11.5)),
                              onPressed: () =>
                                  setSt(() => labelCtrl.text = s),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: grade,
                    decoration: const InputDecoration(
                      labelText: '어느 학년이 쉬나요',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('전 학년')),
                      for (final g in grades)
                        DropdownMenuItem(value: g, child: Text('$g학년')),
                    ],
                    onChanged: (v) => setSt(() => grade = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pick(true),
                          child: Text(
                              '시작 ${DateFormat('M/d').format(start)}',
                              style: GoogleFonts.notoSansKr(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pick(false),
                          child: Text('종료 ${DateFormat('M/d').format(end)}',
                              style: GoogleFonts.notoSansKr(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    grade == null
                        ? '이 기간에는 모든 학년이 투표를 쉬어요.'
                        : '이 기간에는 $grade학년만 투표를 쉬고, '
                            '나머지 학년은 그대로 투표합니다.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    try {
      await ref.read(voteRepositoryProvider).addBlackout(
            schoolId: schoolId,
            grade: grade,
            startDate: start,
            endDate: end,
            label: labelCtrl.text,
          );
      ref.invalidate(voteBlackoutsProvider);
      final round = ref.read(openRoundProvider);
      if (round != null) ref.invalidate(voteProgressProvider(round.id));
      ref.invalidate(voteHintProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  // ── 진행 중인 투표 수정 (관리자) ───────────────────────────
  //   학기 시작 때 투표 기간과 요일을 미리 잡아두면, 그 밖의 날에는
  //   투표 버튼이 잠기고 이유가 화면에 표시된다.
  Future<void> _showEditRound(VoteRound round) async {
    final titleCtrl = TextEditingController(text: round.title);
    var votes = round.votesPerWeek;
    var weeks = round.totalWeeks;
    DateTime? start = round.startDate;
    DateTime? end = round.endDate;
    final days = {...round.voteWeekdays};

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSt) {
          Future<void> pick(bool isStart) async {
            final base = (isStart ? start : end) ?? DateTime.now();
            final picked = await showDatePicker(
              context: sheetCtx,
              initialDate: base,
              firstDate: DateTime(base.year - 1),
              lastDate: DateTime(base.year + 2),
            );
            if (picked == null) return;
            setSt(() {
              if (isStart) {
                start = picked;
                if (end != null && end!.isBefore(picked)) end = picked;
              } else {
                end = (start != null && picked.isBefore(start!)) ? start : picked;
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('✏️', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('투표 수정',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 17, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetCtx, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '투표 이름',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: votes,
                          decoration: const InputDecoration(
                            labelText: '주당 투표권',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (var v = 1; v <= 10; v++)
                              DropdownMenuItem(value: v, child: Text('$v표')),
                          ],
                          onChanged: (v) => setSt(() => votes = v ?? votes),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: weeks,
                          decoration: const InputDecoration(
                            labelText: '총 주차',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (var w = 1; w <= 20; w++)
                              DropdownMenuItem(value: w, child: Text('$w주')),
                          ],
                          onChanged: (v) => setSt(() => weeks = v ?? weeks),
                        ),
                      ),
                    ],
                  ),
                  const SectionHeader(title: '🗓️ 투표 기간'),
                  Text(
                    '학기 시작 때 미리 잡아두시면 그 기간에만 투표가 열립니다. '
                    '비워두시면 기한 없이 진행돼요.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pick(true),
                          child: Text(
                            start == null
                                ? '시작일 없음'
                                : '시작 ${DateFormat('M/d').format(start!)}',
                            style: GoogleFonts.notoSansKr(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pick(false),
                          child: Text(
                            end == null
                                ? '종료일 없음'
                                : '종료 ${DateFormat('M/d').format(end!)}',
                            style: GoogleFonts.notoSansKr(fontSize: 13),
                          ),
                        ),
                      ),
                      if (start != null || end != null)
                        IconButton(
                          tooltip: '기간 지우기',
                          icon: const Icon(Icons.backspace_outlined, size: 18),
                          onPressed: () => setSt(() {
                            start = null;
                            end = null;
                          }),
                        ),
                    ],
                  ),
                  const SectionHeader(title: '📅 투표 가능한 요일'),
                  Text(
                    '고르지 않으시면 수업일 아무 때나 투표할 수 있어요. '
                    '금요일만 고르시면 한 주를 지켜본 뒤 투표하게 됩니다.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var d = 1; d <= 5; d++)
                        FilterChip(
                          label: Text(
                            ['월', '화', '수', '목', '금'][d - 1],
                            style: GoogleFonts.notoSansKr(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          selected: days.contains(d),
                          selectedColor:
                              AppColors.teacherNavy.withValues(alpha: 0.18),
                          onSelected: (on) => setSt(
                              () => on ? days.add(d) : days.remove(d)),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.lg),
                  PbsPrimaryButton(
                    label: '저장',
                    color: AppColors.teacherNavy,
                    onPressed: () => Navigator.pop(sheetCtx, true),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, null),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.danger),
                    label: Text('이 투표 삭제',
                        style: GoogleFonts.notoSansKr(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: AppSizes.md),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    if (saved == null) {
      await _confirmDeleteRound(round);
      return;
    }
    if (saved != true) return;

    try {
      await ref.read(voteRepositoryProvider).updateRound(
            roundId: round.id,
            title: titleCtrl.text,
            votesPerWeek: votes,
            totalWeeks: weeks,
            startDate: start,
            endDate: end,
            weekdays: days.toList(),
          );
      _refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  /// 라운드 삭제 — 그 라운드의 투표 기록도 함께 사라지므로 표 수를 알려주고 묻는다.
  Future<void> _confirmDeleteRound(VoteRound round) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('투표 삭제',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '"${round.title}" 을(를) 삭제할까요?\n\n'
          '이 투표에 들어온 표와 학년별 설정이 모두 함께 지워지고,\n'
          '되돌릴 수 없어요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref.read(voteRepositoryProvider).deleteRound(round.id);
      _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제했어요. (투표 $n표 함께 삭제)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  // ── 투표 안내 알림 발송 (관리자) ───────────────────────────
  Future<void> _confirmSendNotice(VoteRound round) async {
    final bodyCtrl = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('투표 안내 보내기',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '우리 학교 선생님들께 수업맛집 투표 알림을 보냅니다.\n'
              '비워두시면 기본 안내 문구로 나갑니다.',
              style: GoogleFonts.notoSansKr(fontSize: 12.5, height: 1.6),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '보낼 말 (선택)',
                hintText: '예: 오늘까지 투표해주세요!',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('취소')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (send != true) return;
    try {
      await ref.read(voteRepositoryProvider).sendNotice(
            roundId: round.id,
            body: bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선생님들께 투표 안내를 보냈어요.')),
        );
      }
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

/// 라운드에 지정된 투표 기간·요일을 한 줄로. 지정이 없으면 null.
String? _scheduleLine(VoteRound round) {
  final parts = <String>[];
  final f = DateFormat('M/d');
  if (round.startDate != null || round.endDate != null) {
    parts.add('${round.startDate == null ? "" : f.format(round.startDate!)}'
        '~'
        '${round.endDate == null ? "" : f.format(round.endDate!)}');
  }
  final w = round.weekdayLabel;
  if (w != null) parts.add(w);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 안내 한 줄 상자 — 오늘 투표할 수 없는 이유 등.
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.teacherNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.teacherNavy.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.teacherNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.teacherNavy)),
          ),
        ],
      ),
    );
  }
}

class _RoundHeader extends ConsumerWidget {
  const _RoundHeader({required this.round});
  final VoteRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = ref.watch(voteProgressProvider(round.id)).value ??
        VoteProgress.empty;
    final progress = prog.grades;

    return PbsCard(
      color: AppColors.teacherNavy,
      border: Border.all(color: AppColors.teacherNavy),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(round.title,
              style: GoogleFonts.notoSansKr(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            '매주 우리 학교 수업 규칙을 가장 잘 실천한 학급에 투표해주세요. '
            '교사 1인당 주 ${round.votesPerWeek}표, 매주 새로 투표할 수 있어요.',
            style: GoogleFonts.notoSansKr(
                fontSize: 12, color: Colors.white70, height: 1.5),
          ),
          if (_scheduleLine(round) != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('🗓️ ${_scheduleLine(round)}',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70)),
            ),
          if (progress.isNotEmpty) ...[
            const SizedBox(height: 10),
            // 학년마다 시험 일정이 달라 주차가 따로 흐른다.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: progress.map((p) {
                final dim = !p.isVotable;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: dim ? 0.10 : 0.20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    p.closed
                        ? '🏆 ${p.grade}학년 마감'
                        : p.isPaused
                            ? '⏸ ${p.grade}학년 ${p.pausedLabel}'
                            : '${p.grade}학년 ${p.weekNow}/${p.totalWeeks}주차',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: dim ? Colors.white60 : Colors.white,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 지금 투표를 받지 않는 학년 안내 — 시험 기간이거나 먼저 마감된 학년.
class _PausedGradesNotice extends StatelessWidget {
  const _PausedGradesNotice({required this.blocked});
  final List<VoteGradeProgress> blocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocked
            .map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    p.closed
                        ? '${p.grade}학년은 먼저 마감돼서 투표할 수 없어요.'
                        : '${p.grade}학년은 ${p.pausedLabel} 기간이라 지금은 투표하지 않아요.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, height: 1.5, color: Colors.brown),
                  ),
                ))
            .toList(),
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
            Row(
              children: [
                Expanded(
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
                    ],
                  ),
                ),
                // 지난 결과가 쌓이면 관리자가 정리할 수 있어야 한다.
                if (ref.watch(profileProvider).value?.isAdminTeacher ?? false)
                  IconButton(
                    tooltip: '이 결과 삭제',
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 19, color: AppColors.textTertiary),
                    onPressed: () => _confirmDeleteClosedRound(context, ref, round),
                  ),
              ],
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

/// 학년 한 줄 — 주차 조정과 조기 마감. 관리자 시트에서만 쓴다.
class _GradeScheduleRow extends ConsumerWidget {
  const _GradeScheduleRow({required this.round, required this.p});
  final VoteRound round;
  final VoteGradeProgress p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> run(Future<void> Function() task) async {
      try {
        await task();
        ref.invalidate(voteProgressProvider(round.id));
        ref.invalidate(voteTallyProvider(round.id));
        ref.invalidate(voteHintProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(translateError(e))));
        }
      }
    }

    final chipColor = p.closed
        ? AppColors.textTertiary
        : p.isPaused
            ? AppColors.warning
            : p.isFinished
                ? AppColors.studentGreen
                : AppColors.teacherNavy;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${p.grade}학년',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(p.statusText,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: chipColor)),
                ),
                const Spacer(),
                Text('${p.votes}표',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    // 0 = 라운드 기본값 사용
                    value: p.customWeeks ? p.totalWeeks : 0,
                    decoration: const InputDecoration(
                      labelText: '총 주차',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 0,
                          child: Text('기본 ${round.totalWeeks}주',
                              style:
                                  GoogleFonts.notoSansKr(fontSize: 13))),
                      for (var w = 1; w <= 20; w++)
                        DropdownMenuItem(
                            value: w,
                            child: Text('$w주',
                                style:
                                    GoogleFonts.notoSansKr(fontSize: 13))),
                    ],
                    onChanged: p.closed
                        ? null
                        : (v) => run(() => ref
                            .read(voteRepositoryProvider)
                            .setGradeWeeks(
                                roundId: round.id,
                                grade: p.grade,
                                weeks: (v == null || v == 0) ? null : v)),
                  ),
                ),
                const SizedBox(width: 8),
                if (p.closed)
                  OutlinedButton(
                    onPressed: () => run(() => ref
                        .read(voteRepositoryProvider)
                        .setGradeClosed(
                            roundId: round.id,
                            grade: p.grade,
                            closed: false)),
                    child: Text('마감 취소',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teacherNavy),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: Text('${p.grade}학년 먼저 마감',
                              style: GoogleFonts.notoSansKr(
                                  fontWeight: FontWeight.w900)),
                          content: Text(
                            '${p.grade}학년 투표를 지금 마감할까요?\n\n'
                            '${p.grade}학년은 더 이상 투표를 받지 않고,\n'
                            '결과가 모든 선생님께 공개돼요.\n'
                            '다른 학년은 그대로 계속 투표합니다.',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 13, height: 1.6),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogCtx, false),
                                child: const Text('취소')),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialogCtx, true),
                              child: const Text('마감하기'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await run(() => ref
                          .read(voteRepositoryProvider)
                          .setGradeClosed(
                              roundId: round.id,
                              grade: p.grade,
                              closed: true));
                    },
                    child: Text('먼저 마감',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 등록된 쉬는 기간 한 줄.
class _BlackoutTile extends ConsumerWidget {
  const _BlackoutTile({required this.blackout});
  final VoteBlackout blackout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = blackout.containsToday();
    final f = DateFormat('M/d');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: PbsCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md, vertical: AppSizes.sm),
        child: Row(
          children: [
            Text(now ? '⏸' : '🗓️', style: const TextStyle(fontSize: 17)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${blackout.gradeLabel} · ${blackout.label}',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text(
                    '${f.format(blackout.startDate)} ~ '
                    '${f.format(blackout.endDate)}'
                    '${now ? "  ·  진행 중" : ""}',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        color: now
                            ? AppColors.warning
                            : AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 19, color: AppColors.textTertiary),
              onPressed: () async {
                try {
                  await ref
                      .read(voteRepositoryProvider)
                      .deleteBlackout(blackout.id);
                  ref.invalidate(voteBlackoutsProvider);
                  ref.invalidate(voteHintProvider);
                  final round = ref.read(openRoundProvider);
                  if (round != null) {
                    ref.invalidate(voteProgressProvider(round.id));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(translateError(e))));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 라운드가 아직 열려 있어도, 먼저 마감된 학년(예: 3학년)의 결과는 모두에게 공개.
class _EarlyClosedResults extends ConsumerWidget {
  const _EarlyClosedResults({required this.round});
  final VoteRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = (ref.watch(voteProgressProvider(round.id)).value ??
            VoteProgress.empty)
        .grades;
    final closedGrades =
        progress.where((p) => p.closed).map((p) => p.grade).toSet();
    if (closedGrades.isEmpty) return const SizedBox.shrink();

    final rows = ref.watch(voteTallyProvider(round.id)).value ??
        const <VoteTallyRow>[];
    // rows 는 학년별 득표순 → 학년마다 첫 항목이 1위
    final winners = <int, VoteTallyRow>{};
    for (final r in rows) {
      if (closedGrades.contains(r.grade)) {
        winners.putIfAbsent(r.grade, () => r);
      }
    }
    final grades = closedGrades.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '🏆 먼저 마감된 학년 결과'),
        PbsCard(
          color: const Color(0xFFFEF9E7),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: grades.map((g) {
              final w = winners[g];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  w == null
                      ? '$g학년 — 투표 기록이 없어요.'
                      : '🏆 ${w.classLabel} (${w.votes}표)',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: const Color(0xFFB45309)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// 지난 투표 결과 삭제 — 표까지 함께 사라지므로 한 번 더 묻는다.
Future<void> _confirmDeleteClosedRound(
    BuildContext context, WidgetRef ref, VoteRound round) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text('지난 결과 삭제',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      content: Text(
        '"${round.title}" 결과를 목록에서 지울까요?\n\n'
        '그 투표에 들어온 표도 함께 지워지고, 되돌릴 수 없어요.',
        style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: const Text('삭제하기'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(voteRepositoryProvider).deleteRound(round.id);
    ref.invalidate(voteRoundsProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    }
  }
}
