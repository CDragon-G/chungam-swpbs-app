import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../providers/calendar_provider.dart';

/// 📅 학사일정 — 방학·재량휴업일 등록.
/// 등록한 기간에는 자기점검이 열리지 않고 알림도 가지 않는다.
/// 주말과 공휴일은 자람이 자동으로 처리한다.
class SchoolCalendarScreen extends ConsumerWidget {
  const SchoolCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;
    final closures = ref.watch(schoolClosuresProvider);
    final holidays = ref.watch(publicHolidaysProvider);
    final today = ref.watch(todaySchoolStatusProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📅 학사일정',
                style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('방학 · 재량휴업일 등록',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
      floatingActionButton: !isAdmin
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.teacherNavy,
              onPressed: () => _showAddSheet(context, ref),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('휴업일 등록',
                  style: GoogleFonts.notoSansKr(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(schoolClosuresProvider);
          ref.invalidate(todaySchoolStatusProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            // 오늘 상태
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: (today?.isSchoolDay ?? true)
                    ? AppColors.studentGreenLight
                    : const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(
                    color: (today?.isSchoolDay ?? true)
                        ? AppColors.studentGreen.withValues(alpha: 0.35)
                        : const Color(0xFFF5D08C)),
              ),
              child: Row(
                children: [
                  Text((today?.isSchoolDay ?? true) ? '📗' : '🌿',
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (today?.isSchoolDay ?? true)
                          ? '오늘은 수업일이에요 — 자기점검이 열려 있어요'
                          : today!.teacherMessage,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                          color: (today?.isSchoolDay ?? true)
                              ? AppColors.success
                              : const Color(0xFF9A6A0B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),

            const _InfoBox(),

            const SectionHeader(title: '🏫 우리 학교 휴업일'),
            closures.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(translateError(e),
                  style: GoogleFonts.notoSansKr(fontSize: 13)),
              data: (list) {
                if (list.isEmpty) {
                  return PbsCard(
                    child: Text(
                      isAdmin
                          ? '아직 등록된 휴업일이 없어요.\n방학과 재량휴업일을 등록하면 그 기간에는\n점검과 알림이 모두 멈춰요.'
                          : '아직 등록된 휴업일이 없어요.\n리더십팀(관리자) 선생님께 요청해주세요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          height: 1.6,
                          color: AppColors.textTertiary),
                    ),
                  );
                }
                return Column(
                  children: list
                      .map((c) => _ClosureRow(closure: c, isAdmin: isAdmin))
                      .toList(),
                );
              },
            ),

            const SectionHeader(title: '🇰🇷 공휴일 (자동 적용)'),
            holidays.when(
              loading: () => const SizedBox(height: 40),
              error: (e, _) => const SizedBox.shrink(),
              data: (list) => PbsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('공휴일은 자람이 자동으로 반영해요. 등록하지 않으셔도 됩니다.',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    ...list.take(12).map((h) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 96,
                                child: Text(
                                  DateFormat('M월 d일 (E)', 'ko').format(
                                      DateTime.parse(
                                          h['holiday_date'] as String)),
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary),
                                ),
                              ),
                              Text(h['name'] as String,
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 12.5)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 휴업일 등록 시트 — 하루 또는 기간.
  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final label = TextEditingController();
    DateTime? start;
    DateTime? end;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: AppSizes.xl,
              right: AppSizes.xl,
              top: AppSizes.xl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('📅 휴업일 등록',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('예: 여름방학, 겨울방학, 재량휴업일, 개교기념일',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12, color: AppColors.textTertiary)),
              const SizedBox(height: 14),

              // 빠른 선택 칩
              Wrap(
                spacing: 6,
                children: ['여름방학', '겨울방학', '봄방학', '재량휴업일', '개교기념일']
                    .map((t) => ActionChip(
                          label: Text(t,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          onPressed: () => setSheet(() => label.text = t),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: label,
                style: GoogleFonts.notoSansKr(fontSize: 14),
                decoration: InputDecoration(
                  labelText: '이름',
                  labelStyle: GoogleFonts.notoSansKr(fontSize: 13),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(
                          start == null
                              ? '시작일'
                              : DateFormat('M/d(E)', 'ko').format(start!),
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w700)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(DateTime.now().year - 1),
                          lastDate: DateTime(DateTime.now().year + 2),
                        );
                        if (d != null) {
                          setSheet(() {
                            start = d;
                            end ??= d;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text(
                          end == null
                              ? '종료일'
                              : DateFormat('M/d(E)', 'ko').format(end!),
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w700)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: start ?? DateTime.now(),
                          firstDate: start ?? DateTime(DateTime.now().year - 1),
                          lastDate: DateTime(DateTime.now().year + 2),
                        );
                        if (d != null) setSheet(() => end = d);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('하루만 쉬는 날은 시작일과 종료일을 같게 하세요.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5, color: AppColors.textTertiary)),
              const SizedBox(height: 14),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
                onPressed: () async {
                  final schoolId = ref.read(profileProvider).value?.schoolId;
                  if (schoolId == null ||
                      start == null ||
                      end == null ||
                      label.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('이름과 기간을 모두 입력해주세요.')),
                    );
                    return;
                  }
                  await ref.read(calendarRepositoryProvider).addClosure(
                        schoolId: schoolId,
                        start: start!,
                        end: end!,
                        label: label.text.trim(),
                      );
                  ref.invalidate(schoolClosuresProvider);
                  ref.invalidate(todaySchoolStatusProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('등록',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.teacherNavyLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🌿 쉬는 날에는 이렇게 동작해요',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.teacherNavy)),
          const SizedBox(height: 6),
          ...[
            '학생 홈에 "오늘은 쉬는 날" 안내가 뜨고 점검 버튼이 잠겨요',
            '자기점검 알림이 가지 않아요',
            '주간 개근 보너스는 그 주 수업일 수를 기준으로 계산돼요',
          ].map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('· ',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 13, color: AppColors.textSecondary)),
                    Expanded(
                      child: Text(t,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ClosureRow extends ConsumerWidget {
  const _ClosureRow({required this.closure, required this.isAdmin});
  final Map<String, dynamic> closure;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = DateTime.parse(closure['start_date'] as String);
    final end = DateTime.parse(closure['end_date'] as String);
    final days = end.difference(start).inDays + 1;
    final fmt = DateFormat('M월 d일', 'ko');
    final now = DateTime.now();
    final isPast = end.isBefore(DateTime(now.year, now.month, now.day));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(closure['label'] as String,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: isPast
                              ? AppColors.textTertiary
                              : AppColors.textPrimary)),
                  Text(
                    days == 1
                        ? fmt.format(start)
                        : '${fmt.format(start)} ~ ${fmt.format(end)} ($days일)',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (isPast)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('지남',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textTertiary)),
              ),
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppColors.textTertiary),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      title: const Text('휴업일 삭제'),
                      content: Text('${closure['label']}을(를) 삭제할까요?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            child: const Text('취소')),
                        FilledButton(
                            onPressed: () => Navigator.pop(dialogCtx, true),
                            child: const Text('삭제')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await ref
                      .read(calendarRepositoryProvider)
                      .deleteClosure(closure['id'] as String);
                  ref.invalidate(schoolClosuresProvider);
                  ref.invalidate(todaySchoolStatusProvider);
                },
              ),
          ],
        ),
      ),
    );
  }
}
