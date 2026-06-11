import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../points/providers/points_provider.dart';
import '../../school/providers/school_provider.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _State();
}

class _State extends ConsumerState<StudentListScreen> {
  String _filterGrade = '전체';

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(schoolStudentsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '학생 관리',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (students) {
          final grades = {'전체', for (final s in students) '${s['grade']}학년'};
          final filtered = _filterGrade == '전체'
              ? students
              : students
                  .where((s) => '${s['grade']}학년' == _filterGrade)
                  .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSizes.lg),
                child: Wrap(
                  spacing: 6,
                  children: grades.map((g) {
                    final selected = _filterGrade == g;
                    return ChoiceChip(
                      label: Text(g),
                      selected: selected,
                      onSelected: (_) => setState(() => _filterGrade = g),
                      selectedColor: AppColors.teacherNavy,
                      labelStyle: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(color: AppColors.borderLight),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: PbsCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.teacherNavy,
                              child: Text(
                                ((s['nickname'] as String).characters.isEmpty
                                    ? '?'
                                    : (s['nickname'] as String).characters.first),
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['nickname'] as String,
                                    style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${s['grade']}학년 ${s['class_num']}반 ${s['student_num']}번',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _StudentPoints(userId: s['user_id'] as String),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentPoints extends ConsumerWidget {
  const _StudentPoints({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(
      FutureProvider<int>((ref) async =>
          ref.read(pointsRepositoryProvider).userBalance(userId)),
    );
    return balanceAsync.maybeWhen(
      data: (p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.studentGreenLight,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${NumberFormat('#,###').format(p)}P',
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.studentGreen,
          ),
        ),
      ),
      orElse: () => const SizedBox(width: 40, height: 20),
    );
  }
}
