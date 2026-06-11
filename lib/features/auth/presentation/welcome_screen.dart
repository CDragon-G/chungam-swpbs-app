import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OnboardingDialog.showIfFirstLaunch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.studentGreen],
                  ),
                  borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                ),
                child: const Text('🌱', style: TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.appSubtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                AppStrings.slogan,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              PbsPrimaryButton(
                label: '교사로 시작하기',
                icon: Icons.school_rounded,
                color: AppColors.teacherNavy,
                onPressed: () => context.go('/signup/teacher'),
              ),
              const SizedBox(height: AppSizes.md),
              PbsPrimaryButton(
                label: '학생으로 시작하기',
                icon: Icons.person_rounded,
                color: AppColors.studentGreen,
                onPressed: () => context.go('/signup/student'),
              ),
              const SizedBox(height: AppSizes.md),
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
              const SizedBox(height: AppSizes.md),
            ],
          ),
        ),
      ),
    );
  }
}
