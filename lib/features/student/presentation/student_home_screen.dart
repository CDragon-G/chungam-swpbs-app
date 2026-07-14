import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/notifications/reminder_prefs.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../checkin/providers/checkin_provider.dart';
import '../../cico/providers/cico_provider.dart';
import '../../growth/models/growth_status.dart';
import '../../growth/presentation/farm_widgets.dart';
import '../../growth/presentation/school_sprout_card.dart';
import '../../growth/providers/growth_provider.dart';
import '../../school/providers/school_provider.dart';
import '../../vote/presentation/vote_hint_card.dart';
import '../../vote/providers/vote_provider.dart';
import '../providers/student_stats_provider.dart';

/// 🌾 학생 홈 — 올팜식 농장 화면.
/// 우리 학교 식물을 다 함께 키우고, 오늘 점검이 가장 큰 버튼.
class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  @override
  void initState() {
    super.initState();
    // 학생 첫 진입 시 일일 리마인더 기본 ON (한 번도 설정 안 했을 때만)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReminderPrefs.ensureDefaultOnForStudent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final growth = ref.watch(schoolGrowthProvider).value;
    final stats = ref.watch(studentStatsProvider).value;
    final todayDone = ref.watch(todayCheckinProvider).value != null;
    final hasCico = ref.watch(myCicoProvider).value != null;
    final voteHint = ref.watch(voteHintProvider).value;
    final announcements = ref.watch(announcementsProvider).value;
    final latestNotice =
        (announcements != null && announcements.isNotEmpty)
            ? announcements.first['title'] as String
            : null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(schoolGrowthProvider);
        ref.invalidate(todayCheckinProvider);
        ref.invalidate(studentStatsProvider);
        ref.invalidate(announcementsProvider);
        ref.invalidate(voteHintProvider);
      },
      child: Stack(
        children: [
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
                name: growth?.schoolName ?? '자람 학교',
                onTap: growth == null
                    ? null
                    : () => showGrowthSheet(context, growth),
              ),
            ),
          ),

          // ── 팻말 아래: 최근 공지 배너 ──
          if (latestNotice != null)
            Positioned(
              top: 102,
              left: 62,
              right: 62,
              child: FarmNoticeBanner(
                text: latestNotice,
                onTap: () => _showNoticeSheet(context),
              ),
            ),

          // ── 좌상단: 인사 + 스트릭 ──
          Positioned(
            top: 10,
            left: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${profile?.nickname ?? ''} 🌟',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                ),
                if ((stats?.streak ?? 0) > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED)
                          .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '🔥 ${stats!.streak}일 연속',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309)),
                    ),
                  ),
              ],
            ),
          ),

          // ── 우상단: 로그아웃 ──
          Positioned(
            top: 6,
            right: 8,
            child: GestureDetector(
              onTap: () async {
                await ref.read(authRepositoryProvider).signOut();
                if (context.mounted) context.go('/welcome');
              },
              child: const Icon(
                Icons.logout_rounded,
                size: 25,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
              ),
            ),
          ),

          // ── 좌측: 실행 메뉴 ──
          Positioned(
            left: 6,
            top: 148,
            child: Column(
              children: [
                FarmMenuButton(
                  asset: 'assets/icons/info_status.png',
                  label: '오늘 점검',
                  badge: todayDone ? null : '!',
                  onTap: () => context.go('/student/checkin'),
                ),
                FarmMenuButton(
                  asset: 'assets/icons/menu_fame.png',
                  label: '명예의 전당',
                  onTap: () => context.go('/student/hall-of-fame'),
                ),
                if (hasCico)
                  FarmMenuButton(
                    asset: 'assets/icons/menu_cico.png',
                    label: 'CICO',
                    onTap: () => context.go('/student/cico'),
                  ),
              ],
            ),
          ),

          // ── 우측: 정보 메뉴 ──
          Positioned(
            right: 6,
            top: 148,
            child: Column(
              children: [
                FarmMenuButton(
                  asset: 'assets/icons/info_missions.png',
                  label: '성장 미션',
                  onTap: growth == null
                      ? () {}
                      : () => showGrowthSheet(context, growth),
                ),
                if (voteHint?.hasRound == true)
                  FarmMenuButton(
                    asset: 'assets/icons/menu_vote.png',
                    label: '수업맛집',
                    onTap: () => _showVoteHintSheet(context),
                  ),
              ],
            ),
          ),

          // ── 하단 고정: 말풍선 + 식물 + 진행바 (CTA 바로 위) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 76,
            child: GestureDetector(
              onTap: growth == null
                  ? null
                  : () => showGrowthSheet(context, growth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlantSpeechBubble(
                    pinned: (growth != null && growth.isGateLocked)
                        ? '양분은 가득 찼어! 🌕\n🔑 "${growth.gateKeyLabel}"\n미션이 끝나면 바로 레벨업이야!'
                        : null,
                    messages: const [
                      '오늘도 와줘서 고마워!\n네 덕분에 쑥쑥 크고 있어 🌱',
                      '규칙을 지키는 너, 진짜 멋져!',
                      '칭찬받으면 나한테도 양분이 와!\n완전 꿀맛이야 💚',
                      '내일도 물 주러 와줘~ 기다릴게!',
                      '우리 반이 수업맛집 되면\n나 꽃 피울지도 몰라 🌸',
                      '조금씩 자라는 게\n제일 튼튼하게 크는 거래 🌿',
                    ],
                  ),
                  BreathingSprout(
                    asset: growth?.levelAsset ?? GrowthStatus.assetFor(1),
                    level: growth?.level ?? 1,
                    size: 172,
                  ),
                  const SizedBox(height: 10),
                  if (growth != null) GrowthProgressBar(growth: growth),
                ],
              ),
            ),
          ),

          // ── 하단: 오늘 점검 CTA ──
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: todayDone
                        ? null
                        : () => context.go('/student/checkin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.studentGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.92),
                      disabledForegroundColor: AppColors.studentGreen,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      todayDone
                          ? '오늘 점검 완료! 새싹이 자랐어요 🌱'
                          : '✅ 오늘 자기점검 하러 가기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🍽️ 수업맛집 진행 현황 시트.
  void _showVoteHintSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('🍽️ 수업맛집 투표 현황',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                '선생님들이 매주 수업 규칙을 잘 지킨 학급에 투표하고 있어요.\n'
                '수업 시간의 좋은 모습이 우리 반을 수업맛집으로 만들어요!',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: AppSizes.md),
              const VoteHintCard(compact: true),
              const SizedBox(height: AppSizes.md),
            ],
          ),
        ),
      ),
    );
  }

  /// 📢 공지 시트.
  void _showNoticeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer(
        builder: (ctx, ref2, __) {
          final anns = ref2.watch(announcementsProvider).value ?? [];
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              maxChildSize: 0.9,
              builder: (c, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(AppSizes.xl),
                children: [
                  Text('📢 학교 공지',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: AppSizes.md),
                  if (anns.isEmpty)
                    Text('아직 공지가 없어요.',
                        style: GoogleFonts.notoSansKr(
                            color: AppColors.textTertiary))
                  else
                    ...anns.take(10).map((a) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(AppSizes.md),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a['title'] as String,
                                  style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(a['body'] as String,
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
