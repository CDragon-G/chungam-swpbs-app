import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../school/providers/school_provider.dart';
import '../providers/dashboard_provider.dart';

class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final school = ref.watch(schoolProvider);
    final overview = ref.watch(schoolOverviewProvider);
    final announcements = ref.watch(announcementsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(schoolOverviewProvider);
        ref.invalidate(schoolStudentsProvider);
        ref.invalidate(announcementsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '안녕하세요, ${profile?.nickname ?? ''} 선생님',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (profile != null && profile.isTeacher) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: profile.isAdminTeacher
                              ? AppColors.primary
                              : AppColors.borderLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          profile.isAdminTeacher
                              ? '👑 관리자'
                              : '👤 일반 교사',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: profile.isAdminTeacher
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '계정',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onPressed: () => _showAccountMenu(context, ref),
              ),
            ],
          ),
          // Admin-only: teacher permissions card
          if (profile != null && profile.isAdminTeacher) ...[
            const SizedBox(height: AppSizes.md),
            PbsCard(
              onTap: () => context.go('/teacher/permissions'),
              color: AppColors.primaryLight,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              child: Row(
                children: [
                  const Text('👑', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '교사 권한 관리',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
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
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            PbsCard(
              onTap: () => context.go('/teacher/roster'),
              color: AppColors.teacherNavyLight,
              border:
                  Border.all(color: AppColors.teacherNavy.withValues(alpha: 0.2)),
              child: Row(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '학생 명단 관리',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                            color: AppColors.teacherNavy,
                          ),
                        ),
                        Text(
                          '전교생 명단 등록 / 학번 PIN 발급',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppColors.textTertiary),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSizes.md),
          // School info card
          school.when(
            loading: () => const PbsCard(child: SizedBox(height: 100)),
            error: (e, _) => PbsCard(child: Text('오류: $e')),
            data: (sc) {
              if (sc == null) return const SizedBox.shrink();
              return PbsCard(
                color: AppColors.teacherNavy,
                border: Border.all(color: AppColors.teacherNavy),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sc.name,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${sc.region} · ${sc.level}',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '학교 코드',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                sc.schoolCode,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '복사',
                            color: Colors.white,
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: sc.schoolCode));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('학교 코드를 복사했어요')),
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'QR 코드',
                            color: Colors.white,
                            icon: const Icon(Icons.qr_code_rounded),
                            onPressed: () => _showQr(context, sc.schoolCode, sc.name),
                          ),
                        ],
                      ),
                    ),
                    // 교사 코드: 관리자에게만 표시 (동료 교사 가입용)
                    if (profile != null &&
                        profile.isAdminTeacher &&
                        sc.teacherCode != null) ...[
                      const SizedBox(height: AppSizes.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.lock_rounded,
                                        size: 12, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(
                                      '교사 코드 (동료 교사 가입용)',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  sc.teacherCode!,
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '교사 코드 복사',
                              color: Colors.white,
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: sc.teacherCode!));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('교사 코드를 복사했어요')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '⚠️ 학생에게는 공유하지 마세요. 동료 교사에게만 개별 전달하세요.',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          // Today quick stats
          const SizedBox(height: AppSizes.md),
          PbsCard(
            onTap: () => context.go('/teacher/hall-of-fame'),
            color: const Color(0xFFFEF9E7),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('명예의 전당',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFB45309))),
                      Text('이달의 학생 (전교·학년·학급)',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: AppColors.textTertiary),
              ],
            ),
          ),
          const SectionHeader(title: '📊 오늘 현황'),
          overview.when(
            loading: () => const PbsCard(child: SizedBox(height: 100)),
            error: (e, _) => PbsCard(child: Text('오류: $e')),
            data: (o) => PbsCard(
              child: Row(
                children: [
                  _StatCell(
                    label: '참여율',
                    value: '${o.todayParticipationPct.round()}%',
                    color: AppColors.scoreColor(o.todayParticipationPct),
                  ),
                  _Divider(),
                  _StatCell(
                    label: '참여 학생',
                    value: '${o.todayParticipants} / ${o.totalStudents}',
                    color: AppColors.teacherNavy,
                  ),
                  _Divider(),
                  _StatCell(
                    label: '주간 평균',
                    value: '${o.weeklyAvg.round()}%',
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          // Class participation quick bars
          overview.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (o) {
              if (o.classParticipation.isEmpty) return const SizedBox.shrink();
              final entries = o.classParticipation.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              return Column(
                children: [
                  const SectionHeader(title: '반별 참여율'),
                  PbsCard(
                    child: Column(
                      children: entries.map((e) {
                        final parts = e.key.split('-');
                        final label = '${parts[0]}학년 ${parts[1]}반';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 84,
                                child: Text(
                                  label,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: AppColors.borderLight,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: (e.value / 100).clamp(0, 1),
                                      child: Container(
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: AppColors.scoreColor(e.value),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${e.value.round()}%',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
          // Announcements
          SectionHeader(
            title: '📢 최근 공지',
            action: TextButton.icon(
              onPressed: () => context.go('/teacher/announce'),
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: Text(
                '공지 쓰기',
                style: GoogleFonts.notoSansKr(fontSize: 12),
              ),
            ),
          ),
          announcements.when(
            loading: () => const PbsCard(child: SizedBox(height: 60)),
            error: (e, _) => PbsCard(child: Text('오류: $e')),
            data: (anns) {
              if (anns.isEmpty) {
                return PbsCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 등록된 공지가 없어요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: anns.take(3).map((a) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: PbsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['title'] as String,
                            style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            a['body'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAccountMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: AppColors.textSecondary),
              title: Text(
                '로그아웃',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await ref.read(authRepositoryProvider).signOut();
                if (context.mounted) context.go('/welcome');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_remove_rounded,
                  color: AppColors.danger),
              title: Text(
                '회원 탈퇴',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              subtitle: Text(
                '계정과 모든 기록이 영구 삭제됩니다',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDeleteAccount(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('회원 탈퇴',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '정말 탈퇴하시겠어요?\n\n'
          '• 계정 정보와 관련 기록이 모두 영구적으로 삭제됩니다.\n'
          '• 삭제된 데이터는 복구할 수 없습니다.\n'
          '• 학교 관리자인 경우, 탈퇴 전 다른 교사에게 관리자\n'
          '  권한을 넘겨주는 것을 권장합니다.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('탈퇴하기',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      ref.invalidate(profileProvider);
      if (!context.mounted) return;
      Navigator.pop(context);
      context.go('/welcome');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('회원 탈퇴가 완료되었습니다.',
              style: GoogleFonts.notoSansKr()),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('탈퇴 실패',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Text(translateError(e),
              style: GoogleFonts.notoSansKr(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('확인', style: GoogleFonts.notoSansKr()),
            ),
          ],
        ),
      );
    }
  }

  void _showQr(BuildContext context, String code, String schoolName) {
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
            Text(
              schoolName,
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '학생들에게 이 코드를 보여주세요',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            QrImageView(
              data: code,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              code,
              style: GoogleFonts.robotoMono(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.notoSansKr(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 36,
        color: AppColors.borderLight,
      );
}
