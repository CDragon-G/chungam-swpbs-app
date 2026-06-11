import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/widgets/pbs_card.dart';

class SignupSelectScreen extends StatelessWidget {
  const SignupSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '어떤 계정으로 시작할까요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '한 번 선택한 역할은 변경할 수 없어요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              PbsCard(
                onTap: () => context.go('/signup/teacher'),
                color: AppColors.teacherNavyLight,
                border: Border.all(color: AppColors.teacherNavy.withValues(alpha: 0.2)),
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.teacherNavy,
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: const Icon(Icons.school_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: AppSizes.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '교사로 시작하기',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teacherNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '학교 등록 · 규칙 관리 · 대시보드',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              PbsCard(
                onTap: () => context.go('/signup/student'),
                color: AppColors.studentGreenLight,
                border: Border.all(color: AppColors.studentGreen.withValues(alpha: 0.25)),
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.studentGreen,
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: AppSizes.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '학생으로 시작하기',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.studentGreen,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '학교 코드로 참여 · 일일 자기점검',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(
                  '이미 계정이 있어요',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
