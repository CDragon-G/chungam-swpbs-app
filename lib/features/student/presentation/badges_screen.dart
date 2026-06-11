import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/models/badge.dart';
import '../providers/badge_provider.dart';

class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allBadges = ref.watch(allBadgesProvider);
    final earned = ref.watch(userBadgesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '뱃지 갤러리',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: allBadges.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (defs) {
          final earnedMap = <String, UserBadge>{
            for (final ub in earned.value ?? const <UserBadge>[]) ub.badgeId: ub,
          };
          return GridView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.95,
              crossAxisSpacing: AppSizes.md,
              mainAxisSpacing: AppSizes.md,
            ),
            itemCount: defs.length,
            itemBuilder: (context, i) {
              final b = defs[i];
              final ub = earnedMap[b.id];
              final earnedThis = ub != null;
              return GestureDetector(
                onTap: () => _showBadgeSheet(context, b, ub),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: earnedThis
                        ? AppColors.surface
                        : AppColors.borderLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                    border: Border.all(
                      color: earnedThis
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.borderLight,
                      width: earnedThis ? 1.5 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(AppSizes.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: earnedThis ? 1 : 0.35,
                        child: Text(b.iconEmoji,
                            style: const TextStyle(fontSize: 48)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        b.name,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: earnedThis
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        earnedThis
                            ? DateFormat('yyyy.MM.dd').format(ub.earnedAt)
                            : b.description,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showBadgeSheet(BuildContext context, BadgeDef b, UserBadge? ub) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(b.iconEmoji, style: const TextStyle(fontSize: 80)),
            const SizedBox(height: AppSizes.md),
            Text(
              b.name,
              style: GoogleFonts.notoSansKr(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              b.description,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            if (ub != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${DateFormat('yyyy년 M월 d일').format(ub.earnedAt)} 획득',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              )
            else
              Text(
                '아직 획득하지 못한 뱃지예요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            const SizedBox(height: AppSizes.lg),
          ],
        ),
      ),
    );
  }
}
