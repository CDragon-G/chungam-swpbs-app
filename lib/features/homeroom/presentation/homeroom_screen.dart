import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../providers/homeroom_provider.dart';

/// 🧑‍🏫 담임반 관리
/// 담임은 해마다·학기 중에도 바뀌므로, 선생님이 직접 학급을 지정하고
/// 언제든 바꿀 수 있게 한다. 지정하면 그 반 학생들의 참여도와 포인트를 본다.
class HomeroomScreen extends ConsumerWidget {
  const HomeroomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeroomOverviewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/teacher/home'),
        ),
        title: Text('담임반 관리',
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          if (async.value?.ok == true)
            TextButton.icon(
              onPressed: () => _pickClass(context, ref),
              icon: const Icon(Icons.swap_horiz_rounded,
                  size: 19, color: AppColors.teacherNavy),
              label: Text('반 변경',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teacherNavy)),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(translateError(e),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.danger)),
          ),
        ),
        data: (o) {
          if (o.needsSetup) return _Setup(onPick: () => _pickClass(context, ref));
          if (!o.ok) {
            return Center(
              child: Text('교사 계정으로 로그인해주세요.',
                  style: GoogleFonts.notoSansKr(
                      color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(homeroomOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg, AppSizes.sm, AppSizes.lg, 90),
              children: [
                _Summary(o: o),
                const SizedBox(height: AppSizes.md),
                _AttentionBanner(o: o),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                  child: Row(
                    children: [
                      Text('학생 ${o.total}명',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 14, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      Text('최근 ${o.days}일 · 수업일 ${o.schoolDays}일 기준',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11.5,
                              color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                ...o.students.map((s) => _StudentTile(s: s)),
                if (o.students.isEmpty)
                  PbsCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '이 학급에 등록된 학생이 없어요.\n'
                        '학급을 다시 확인하시거나 학생 명단 등록을 요청해주세요.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickClass(BuildContext context, WidgetRef ref) async {
    final classes = await ref.read(schoolClassListProvider.future);
    if (!context.mounted) return;

    final current = ref.read(homeroomOverviewProvider).value;
    var grade = current?.grade;
    var classNum = current?.classNum;

    final grades = classes.map((c) => c.grade).toSet().toList()..sort();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final classesOfGrade = classes
              .where((c) => c.grade == grade)
              .toList()
            ..sort((a, b) => a.classNum.compareTo(b.classNum));
          return Padding(
            padding: EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.xl, AppSizes.xl,
                MediaQuery.of(sheetCtx).viewInsets.bottom + AppSizes.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('내 담임 학급 선택',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  '담임이 바뀌면 언제든 다시 선택하시면 됩니다.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
                const SizedBox(height: AppSizes.lg),
                Text('학년',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  children: grades
                      .map((g) => ChoiceChip(
                            label: Text('$g학년'),
                            selected: grade == g,
                            onSelected: (_) => setSheet(() {
                              grade = g;
                              classNum = null;
                            }),
                            selectedColor: AppColors.teacherNavy,
                            labelStyle: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: grade == g
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ))
                      .toList(),
                ),
                if (grade != null) ...[
                  const SizedBox(height: AppSizes.md),
                  Text('반',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    children: classesOfGrade
                        .map((c) => ChoiceChip(
                              label: Text('${c.classNum}반 (${c.studentCount})'),
                              selected: classNum == c.classNum,
                              onSelected: (_) =>
                                  setSheet(() => classNum = c.classNum),
                              selectedColor: AppColors.studentGreen,
                              labelStyle: GoogleFonts.notoSansKr(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: classNum == c.classNum
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: AppSizes.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.teacherNavy),
                  onPressed: (grade == null || classNum == null)
                      ? null
                      : () => Navigator.pop(sheetCtx, true),
                  child: Text('이 학급으로 설정',
                      style:
                          GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok != true || grade == null || classNum == null) return;
    try {
      await ref
          .read(homeroomRepositoryProvider)
          .setHomeroom(grade: grade, classNum: classNum);
      ref.invalidate(homeroomOverviewProvider);
      ref.invalidate(profileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$grade학년 $classNum반으로 설정했어요.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }
}

// ══════════ 담임 학급 미지정 안내 ══════════
class _Setup extends StatelessWidget {
  const _Setup({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧑‍🏫', style: TextStyle(fontSize: 54)),
            const SizedBox(height: AppSizes.lg),
            Text('담임 학급을 먼저 선택해주세요',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: AppSizes.sm),
            Text(
              '선택하시면 그 반 학생들의 자기점검 참여도와\n'
              '포인트를 한 화면에서 보실 수 있어요.\n\n'
              '담임이 바뀌면 언제든 다시 선택하시면 됩니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSizes.xl),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherNavy,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
              ),
              onPressed: onPick,
              child: Text('학급 선택하기',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════ 요약 카드 ══════════
class _Summary extends StatelessWidget {
  const _Summary({required this.o});
  final HomeroomOverview o;

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat('#,###');
    return PbsCard(
      color: AppColors.teacherNavyLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(o.classLabel,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.teacherNavy)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: o.todayPct >= 80
                      ? AppColors.studentGreen
                      : o.todayPct >= 50
                          ? AppColors.warning
                          : AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('오늘 ${o.todayDone}/${o.total}',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: o.total == 0 ? 0 : o.todayDone / o.total,
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.studentGreen),
            ),
          ),
          const SizedBox(height: 4),
          Text('오늘 자기점검 참여율 ${o.todayPct}%',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5, color: AppColors.textSecondary)),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              _Stat(label: '평균 참여율', value: '${o.avgParticipation}%'),
              _Stat(label: '평균 점수', value: '${o.avgScore}점'),
              _Stat(label: '반 전체 포인트', value: f.format(o.totalPoints)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.teacherNavy)),
            Text(label,
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ),
      );
}

// ══════════ 관심 학생 배너 ══════════
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.o});
  final HomeroomOverview o;

  @override
  Widget build(BuildContext context) {
    final list = o.students.where((s) => s.needsAttention).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${list.length}명이 관심이 필요해요 — 3일 이상 점검하지 않았거나 참여율이 낮아요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, height: 1.45, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════ 학생 한 줄 ══════════
class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.s});
  final HomeroomStudent s;

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat('#,###');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        color: s.needsAttention ? AppColors.warning.withValues(alpha: 0.06) : null,
        child: Column(
          children: [
            Row(
              children: [
                // 오늘 점검 여부
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.todayDone
                        ? AppColors.studentGreenLight
                        : AppColors.borderLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    s.todayDone
                        ? Icons.check_rounded
                        : Icons.remove_rounded,
                    size: 19,
                    color: s.todayDone
                        ? AppColors.studentGreen
                        : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${s.studentNum}번',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11.5,
                                  color: AppColors.textTertiary)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              s.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (s.streak >= 3) ...[
                            const SizedBox(width: 5),
                            Text('🔥${s.streak}',
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.warning)),
                          ],
                        ],
                      ),
                      Text(
                        s.neverChecked
                            ? '아직 한 번도 점검하지 않았어요'
                            : '참여 ${s.partPct}% · 평균 ${s.avgScore}점'
                                '${s.missed >= 2 ? " · ${s.missed}일째 미점검" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11.5,
                          fontWeight:
                              s.needsAttention ? FontWeight.w700 : FontWeight.w400,
                          color: s.needsAttention
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${f.format(s.points)}P',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.studentGreen)),
                    if (s.badges > 0)
                      Text('배지 ${s.badges}',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 10.5,
                              color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (s.partPct / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.borderLight,
                valueColor: AlwaysStoppedAnimation(
                  s.partPct >= 80
                      ? AppColors.studentGreen
                      : s.partPct >= 50
                          ? AppColors.warning
                          : AppColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
