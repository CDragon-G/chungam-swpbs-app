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
import '../../calendar/providers/calendar_provider.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/notification_consent.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../quiz/quiz_popup.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../growth/models/growth_status.dart';
import '../../growth/presentation/farm_widgets.dart';
import '../../growth/presentation/school_sprout_card.dart';
import '../../growth/providers/growth_provider.dart';
import '../../onboarding/presentation/teacher_onboarding.dart';
import '../../school/providers/school_provider.dart';
import '../providers/dashboard_provider.dart';

/// 🌾 교사 홈 — 올팜식 농장 화면.
/// 중앙에 학교 공동 식물이 자라고, 좌측은 실행 메뉴, 우측은 정보 메뉴(시트).
class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  @override
  void initState() {
    super.initState();
    // 교사 접속 시 SWPBS 안내 캐로셀 (처음 + 7일마다 다시)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 첫 실행 알림 권한 안내 → SWPBS 캐로셀 → 깜짝 퀴즈 순서
      if (mounted) {
        await NotificationConsent.showIfFirstLaunch(context, isTeacher: true);
      }
      if (mounted) TeacherOnboarding.showIfDue(context);
      checkGrowthLevelUp(ref);
      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted) maybeShowQuizPopup(context, ref, isTeacher: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminTeacher ?? false;
    final growth = ref.watch(schoolGrowthProvider).value;
    final announcements = ref.watch(announcementsProvider).value;
    final latestNotice =
        (announcements != null && announcements.isNotEmpty)
            ? announcements.first['title'] as String
            : null;

    final fs = farmScale(context);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(schoolGrowthProvider);
        ref.invalidate(schoolOverviewProvider);
        ref.invalidate(announcementsProvider);
        ref.invalidate(unreadNotificationCountProvider);
        ref.invalidate(todaySchoolStatusProvider);
      },
      // 농장 홈은 고정 캔버스 화면 — 시스템 글자 확대는 1.1배까지만
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: Stack(
        children: [
          // 스크롤 없는 홈이지만 당겨서 새로고침은 지원
          ListView(physics: const AlwaysScrollableScrollPhysics()),
          // ── 농장 배경 ──
          Positioned.fill(
            child: Image.asset(
              'assets/farm/farm_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
            ),
          ),

          // ── 상단: 학교 팻말 ──
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SchoolSign(
                scale: fs,
                name: growth?.schoolName ?? profile?.nickname ?? '자람 학교',
                onTap: growth == null
                    ? null
                    : () => showGrowthSheet(context, growth),
              ),
            ),
          ),

          // ── 팻말 아래: 최근 공지 배너 ──
          Positioned(
            top: 102 * fs,
            left: 62 * fs,
            right: 62 * fs,
            child: FarmNoticeBanner(
              text: latestNotice ?? '첫 공지를 남겨보세요!',
              onTap: () => context.go('/teacher/announce'),
            ),
          ),

          // ── 우상단: 알림 종 + 설정(계정) 톱니 ──
          Positioned(
            top: 8,
            right: 10,
            child: Row(
              children: [
                const NotificationBell(route: '/teacher/notifications'),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => _showAccountMenu(context, ref),
                  child: const Icon(
                    Icons.settings_rounded,
                    size: 27,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 좌상단: 관리자 배지
          if (isAdmin)
            Positioned(
              top: 12,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('👑 관리자',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),

          // ── 좌측: 실행 메뉴 (스크롤 없이 모두 표시) ──
          Positioned(
            left: 6,
            top: 148 * fs,
            child: Column(
                children: [
                  if (isAdmin)
                    FarmMenuButton(
                      scale: fs,
                      asset: 'assets/icons/menu_permission.png',
                      label: '교사 권한',
                      onTap: () => context.go('/teacher/permissions'),
                    ),
                  if (isAdmin)
                    FarmMenuButton(
                      scale: fs,
                      asset: 'assets/icons/menu_roster.png',
                      label: '학생 명단',
                      onTap: () => context.go('/teacher/roster'),
                    ),
                  FarmMenuButton(
                    scale: fs,
                    asset: 'assets/icons/menu_praise.png',
                    label: '칭찬하기',
                    onTap: () => context.go('/teacher/students'),
                  ),
                  FarmMenuButton(
                    scale: fs,
                    asset: 'assets/icons/menu_kodr.png',
                    label: 'K-ODR',
                    onTap: () => context.go('/teacher/kodr'),
                  ),
                  FarmMenuButton(
                    scale: fs,
                    asset: 'assets/icons/menu_cico.png',
                    label: 'CICO',
                    onTap: () => context.go('/teacher/cico'),
                  ),
                  FarmMenuButton(
                    scale: fs,
                    asset: 'assets/icons/menu_vote.png',
                    label: '수업맛집',
                    onTap: () => context.go('/teacher/vote'),
                  ),
                ],
            ),
          ),

          // ── 우측: 정보 메뉴 (시트) ──
          Positioned(
            right: 6,
            top: 148 * fs,
            child: Column(
              children: [
                FarmMenuButton(
                  scale: fs,
                  asset: 'assets/icons/info_school.png',
                  label: '학교 코드',
                  onTap: () => _showSchoolSheet(context),
                ),
                FarmMenuButton(
                  scale: fs,
                  asset: 'assets/icons/info_status.png',
                  label: '오늘 현황',
                  onTap: () => _showTodaySheet(context),
                ),
                FarmMenuButton(
                  scale: fs,
                  asset: 'assets/icons/info_classes.png',
                  label: '반별 참여',
                  onTap: () => _showClassesSheet(context),
                ),
                FarmMenuButton(
                  scale: fs,
                  asset: 'assets/icons/menu_fame.png',
                  label: '명예의 전당',
                  onTap: () => context.go('/teacher/hall-of-fame'),
                ),
                FarmMenuButton(
                  scale: fs,
                  asset: 'assets/icons/info_missions.png',
                  label: '교사 라운지',
                  onTap: () => context.go('/teacher/lounge'),
                ),
                if (isAdmin)
                  FarmMenuButton(
                    scale: fs,
                    asset: 'assets/icons/info_classes.png',
                    label: '학사일정',
                    onTap: () => context.go('/teacher/calendar'),
                  ),
              ],
            ),
          ),

          // ── 하단 고정: 말풍선 + 식물 + 진행바 (네비 바로 위) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 14 * fs,
            child: GestureDetector(
              onTap: growth == null
                  ? null
                  : () => showGrowthSheet(context, growth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlantSpeechBubble(
                    scale: fs,
                    pinned: (growth != null && growth.isGateLocked)
                        ? '양분은 가득 찼어요! 🌕\n🔑 "${growth.gateKeyLabel}"\n미션이 끝나면 바로 레벨업해요!'
                        : null,
                    messages: const [
                      '선생님의 칭찬 한 마디가\n저에겐 최고의 양분이에요 💚',
                      '오늘도 아이들 곁을\n지켜주셔서 고마워요 🌱',
                      '꾸준한 기록이 학교를 바꿔요.\n선생님, 최고예요!',
                      '수업맛집 투표,\n아이들이 은근히 기다려요 🍽️',
                      '참여율이 오르면\n제 잎이 반짝반짝해져요 ✨',
                      '천천히 자라도 괜찮아요.\n우리 같이 자라는 중이에요 🌿',
                    ],
                  ),
                  BreathingSprout(
                    asset: growth?.levelAsset ?? GrowthStatus.assetFor(1),
                    level: growth?.level ?? 1,
                    size: 172 * fs,
                  ),
                  SizedBox(height: 10 * fs),
                  if (growth != null)
                    GrowthProgressBar(growth: growth, scale: fs),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ═══════════ 정보 시트들 ═══════════

  /// 🏫 학교 코드 시트 (기존 홈의 남색 카드 이동).
  void _showSchoolSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer(
        builder: (ctx, ref2, _) {
          final school = ref2.watch(schoolProvider);
          final profile = ref2.watch(profileProvider).value;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: school.when(
                loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text(translateError(e)),
                data: (sc) {
                  if (sc == null) return const Text('학교 정보가 없어요.');
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(sc.name,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('${sc.region} · ${sc.level}',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: AppSizes.md),
                      Container(
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: AppColors.teacherNavyLight,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('학교 코드 (학생 가입용)',
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                                Text(sc.schoolCode,
                                    style: GoogleFonts.robotoMono(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.teacherNavy,
                                        letterSpacing: 3)),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '복사',
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: sc.schoolCode));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text('학교 코드를 복사했어요')),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'QR 코드',
                              icon: const Icon(Icons.qr_code_rounded),
                              onPressed: () =>
                                  _showQr(ctx, sc.schoolCode, sc.name),
                            ),
                          ],
                        ),
                      ),
                      if ((profile?.isAdminTeacher ?? false) &&
                          sc.teacherCode != null) ...[
                        const SizedBox(height: AppSizes.sm),
                        Container(
                          padding: const EdgeInsets.all(AppSizes.md),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusMd),
                            border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.lock_rounded,
                                        size: 12,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text('교사 코드 (동료 교사 가입용)',
                                        style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            color:
                                                AppColors.textSecondary)),
                                  ]),
                                  Text(sc.teacherCode!,
                                      style: GoogleFonts.robotoMono(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.primary,
                                          letterSpacing: 2)),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '교사 코드 복사',
                                icon: const Icon(Icons.copy_rounded),
                                onPressed: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: sc.teacherCode!));
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('교사 코드를 복사했어요')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '⚠️ 교사 코드는 학생에게 공유하지 마세요. 동료 교사에게만 개별 전달하세요.',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11, color: AppColors.textTertiary),
                        ),
                      ],
                      const SizedBox(height: AppSizes.md),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// 📊 오늘 현황 시트.
  void _showTodaySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer(
        builder: (ctx, ref2, __) {
          final overview = ref2.watch(schoolOverviewProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('📊 오늘 현황',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: AppSizes.md),
                  overview.when(
                    loading: () => const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text(translateError(e)),
                    data: (o) => PbsCard(
                      child: Row(
                        children: [
                          _StatCell(
                            label: '참여율',
                            value: '${o.todayParticipationPct.round()}%',
                            color: AppColors.scoreColor(
                                o.todayParticipationPct),
                          ),
                          _Divider(),
                          _StatCell(
                            label: '참여 학생',
                            value:
                                '${o.todayParticipants} / ${o.totalStudents}',
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
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    '더 자세한 분석은 하단 [대시보드] 탭에서 볼 수 있어요.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: AppSizes.md),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 📈 반별 참여율 시트.
  void _showClassesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer(
        builder: (ctx, ref2, __) {
          final overview = ref2.watch(schoolOverviewProvider);
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (c, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(AppSizes.xl),
                children: [
                  Text('📈 반별 참여율 (오늘)',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: AppSizes.md),
                  overview.when(
                    loading: () => const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text(translateError(e)),
                    data: (o) {
                      if (o.classParticipation.isEmpty) {
                        return Text('아직 참여 데이터가 없어요.',
                            style: GoogleFonts.notoSansKr(
                                color: AppColors.textTertiary));
                      }
                      final entries = o.classParticipation.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key));
                      return PbsCard(
                        child: Column(
                          children: entries.map((e) {
                            final parts = e.key.split('-');
                            final label = '${parts[0]}학년 ${parts[1]}반';
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 84,
                                    child: Text(label,
                                        style: GoogleFonts.notoSansKr(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
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
                                          widthFactor:
                                              (e.value / 100).clamp(0, 1),
                                          child: Container(
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: AppColors.scoreColor(
                                                  e.value),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      999),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${e.value.round()}%',
                                      style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════ 계정 메뉴 (기존 유지) ═══════════

  void _showAccountMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const _MarketingConsentTile(),
            const Divider(height: 1),
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
      if (context.mounted) Navigator.pop(context);
      ref.invalidate(profileProvider);
      if (context.mounted) {
        context.go('/welcome');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('회원 탈퇴가 완료되었습니다.',
                style: GoogleFonts.notoSansKr()),
          ),
        );
      }
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

/// 교사 마케팅(광고성) 이메일 수신동의 토글. 현재 상태를 서버에서 읽어 표시.
class _MarketingConsentTile extends ConsumerStatefulWidget {
  const _MarketingConsentTile();

  @override
  ConsumerState<_MarketingConsentTile> createState() =>
      _MarketingConsentTileState();
}

class _MarketingConsentTileState extends ConsumerState<_MarketingConsentTile> {
  bool? _optIn; // null = 로딩 중

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(authRepositoryProvider).getMarketingConsent();
      if (mounted) setState(() => _optIn = v);
    } catch (_) {
      if (mounted) setState(() => _optIn = false);
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _optIn = v);
    try {
      await ref.read(authRepositoryProvider).setMarketingConsent(v);
    } catch (_) {
      if (mounted) setState(() => _optIn = !v); // 실패 시 되돌림
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _optIn ?? false,
      onChanged: _optIn == null ? null : _toggle,
      activeColor: AppColors.primary,
      secondary: const Icon(Icons.mark_email_read_rounded,
          color: AppColors.textSecondary),
      title: Text(
        '자람 소식 메일 받기',
        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '새 기능·교육자료·혜택 안내 (선택)',
        style: GoogleFonts.notoSansKr(
            fontSize: 11, color: AppColors.textTertiary),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.label, required this.value, required this.color});
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
