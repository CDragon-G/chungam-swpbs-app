import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/student_picker_sheet.dart';
import '../../school/providers/school_provider.dart';
import '../models/cico.dart';
import '../providers/cico_provider.dart';
import 'cico_daily_screen.dart';
import 'cico_start_dialog.dart';

/// 교사: CICO 동행 점검 홈 — 진행 중 학생 목록 + 새 학생 등록.
class CicoHomeScreen extends ConsumerWidget {
  const CicoHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollments = ref.watch(cicoEnrollmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('CICO 동행 점검',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: AppColors.teacherNavy),
            tooltip: 'CICO란?',
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startCico(context, ref),
        backgroundColor: AppColors.teacherNavy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('학생 등록',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(cicoEnrollmentsProvider),
        child: enrollments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text(translateError(e))),
            ),
          ]),
          data: (list) => ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              _banner(),
              const SizedBox(height: AppSizes.md),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(
                    children: [
                      const Text('🤝', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('진행 중인 CICO가 없어요.',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('K-ODR에서 지원이 필요한 학생을 확인하고\n아래 버튼으로 등록해보세요.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                )
              else
                ...list.map((e) => _EnrollmentCard(enrollment: e)),
              const SizedBox(height: 90), // FAB 여백
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.studentGreenLight,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Text(
          '💚 CICO는 멘토 선생님이 매일 함께 점검하며 격려하는 Tier 2 지원이에요. '
          '목표를 꾸준히 달성하면 졸업합니다!',
          style: GoogleFonts.notoSansKr(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.success),
        ),
      );

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('CICO(체크인·체크아웃)란?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '증거기반(EBP) Tier 2 표적 지원 프로그램이에요.\n\n'
          '① 아침: 멘토와 체크인 — 오늘 목표 확인\n'
          '② 하루: 학교 규칙별로 0/1/2 점수\n'
          '③ 하교: 멘토와 체크아웃 — 격려 피드백\n'
          '④ 가정: 학생 소감 + 보호자 확인\n\n'
          '목표 달성률(기본 80%)을 꾸준히 채우면 졸업하고 '
          'Tier 1으로 돌아갑니다. 처벌이 아닌 지원이 목적이에요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('확인',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── 새 학생 등록 ──────────────────────────────────────────
  Future<void> _startCico(BuildContext context, WidgetRef ref) async {
    final students = ref.read(schoolStudentsProvider).value ?? [];
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('등록된 학생이 없어요.')));
      return;
    }
    final student = await StudentPickerSheet.show(context, students,
        title: 'CICO 학생 선택');
    if (student == null || !context.mounted) return;

    await showCicoStartDialog(
      context,
      ref,
      studentUserId: student['user_id'] as String,
      studentName: (student['nickname'] as String?) ?? '학생',
    );
  }

}

// ── 진행 중 카드 ────────────────────────────────────────────
class _EnrollmentCard extends ConsumerWidget {
  const _EnrollmentCard({required this.enrollment});
  final CicoEnrollment enrollment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days =
        KstDate.today().difference(enrollment.startDate).inDays + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CicoDailyScreen(enrollment: enrollment))),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.teacherNavy,
              child: Text(
                (enrollment.studentName ?? '?').characters.isEmpty
                    ? '?'
                    : (enrollment.studentName ?? '?').characters.first,
                style: GoogleFonts.notoSansKr(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${enrollment.studentName ?? '학생'}'
                    '${enrollment.studentLabel == null ? '' : ' (${enrollment.studentLabel})'}',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  Text(
                    '멘토 ${enrollment.mentorName ?? '선생님'} · '
                    '${DateFormat('M/d').format(enrollment.startDate)}~ ($days일차)',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.teacherNavyLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('목표 ${enrollment.goalPct}%',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teacherNavy)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
