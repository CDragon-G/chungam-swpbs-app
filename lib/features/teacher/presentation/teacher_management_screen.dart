import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../school/providers/school_provider.dart';

class TeacherManagementScreen extends ConsumerWidget {
  const TeacherManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final teachersAsync = ref.watch(schoolTeachersProvider);

    if (profile != null && !profile.isAdminTeacher) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go('/teacher/home'),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(
              '🔒 관리자만 접근할 수 있는 페이지예요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/teacher/home'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '교사 권한 관리',
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'SWPBS 리더십팀 임명 / 해제',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '선생님 계정 관리',
            icon: const Icon(Icons.manage_accounts_rounded,
                color: AppColors.teacherNavy),
            onPressed: () => context.go('/teacher/accounts'),
          ),
          IconButton(
            tooltip: '퀴즈 문제 관리',
            icon: const Icon(Icons.quiz_rounded, color: AppColors.teacherNavy),
            onPressed: () => context.go('/teacher/quiz-admin'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(schoolTeachersProvider),
        child: teachersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(translateError(e))),
          data: (teachers) => ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              PbsCard(
                color: AppColors.primaryLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('👑', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(
                          '관리자 (Admin)',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '규칙·교환소·공지 편집 가능. SWPBS 리더십팀에 부여하세요.\n새 학년도에 인사 변동 시 권한 이전 가능합니다.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),
              ...teachers.map((t) => _TeacherRow(
                    teacher: t,
                    isMe: t['user_id'] == profile?.userId,
                  )),
              const SizedBox(height: AppSizes.xxxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherRow extends ConsumerWidget {
  const _TeacherRow({required this.teacher, required this.isMe});
  final Map<String, dynamic> teacher;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = teacher['teacher_role'] == 'admin';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  isAdmin ? AppColors.primary : AppColors.textTertiary,
              child: Text(
                isAdmin ? '👑' : '👤',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        teacher['nickname'] as String,
                        style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '나',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    isAdmin ? '관리자' : '일반 교사',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: isAdmin,
              onChanged: (v) async {
                if (isMe && !v) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('관리자 권한 해제'),
                      content: const Text(
                          '본인의 관리자 권한을 해제하면 더 이상 규칙·교환소·공지를 편집할 수 없어요.\n진행할까요?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소')),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('해제'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                try {
                  await ref.read(schoolRepositoryProvider).setTeacherRole(
                        profileId: teacher['id'] as String,
                        newRole: v ? 'admin' : 'regular',
                      );
                  ref.invalidate(schoolTeachersProvider);
                  ref.invalidate(profileProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(v
                            ? '${teacher['nickname']} → 관리자'
                            : '${teacher['nickname']} → 일반 교사'),
                      ),
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
            ),
          ],
        ),
      ),
    );
  }
}
