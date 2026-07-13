import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/notifications/notifications_service.dart';
import '../../../core/notifications/reminder_prefs.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/category_radar_chart.dart';
import '../../../shared/widgets/monthly_participation_calendar.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../points/providers/points_provider.dart';
import '../../praise/providers/praise_provider.dart';
import '../providers/student_stats_provider.dart';

class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final statsAsync = ref.watch(studentStatsProvider);
    final pointsAsync = ref.watch(myPointsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(studentStatsProvider);
        ref.invalidate(myPointsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxxl,
        ),
        children: [
          // Profile card
          PbsCard(
            color: AppColors.studentGreenLight,
            border: Border.all(color: AppColors.studentGreen.withValues(alpha: 0.2)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.studentGreen,
                  child: Text(
                    (profile?.nickname.characters.first ?? '?'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.nickname ?? '',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        profile?.classLabel ?? '',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                statsAsync.maybeWhen(
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('🔥 ${s.streak}일',
                          style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w800)),
                      Text('총 ${s.totalCount}회',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Points card
          const SectionHeader(title: '🪙 내 포인트'),
          PbsCard(
            color: AppColors.studentGreen,
            border: Border.all(color: AppColors.studentGreen),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 36)),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '보유 포인트',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        '${NumberFormat('#,###').format(pointsAsync.value ?? 0)} P',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.go('/student/store'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.studentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_bag_rounded, size: 16),
                  label: Text(
                    '교환소',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick links row
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _QuickLinkCard(
                  icon: Icons.emoji_events_rounded,
                  label: '뱃지 갤러리',
                  color: AppColors.primary,
                  onTap: () => context.go('/student/badges'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _QuickLinkCard(
                  icon: Icons.receipt_long_rounded,
                  label: '포인트 내역',
                  color: AppColors.studentGreen,
                  onTap: () => context.go('/student/points-history'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _QuickLinkCard(
                  icon: Icons.military_tech_rounded,
                  label: '명예의 전당',
                  color: AppColors.warning,
                  onTap: () => context.go('/student/hall-of-fame'),
                ),
              ),
            ],
          ),

          // 받은 칭찬
          const SectionHeader(title: '💚 선생님께 받은 칭찬'),
          ref.watch(myReceivedPraiseProvider).when(
                loading: () => const PbsCard(
                  child: SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => PbsCard(
                  child: Text('칭찬을 불러오지 못했어요',
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary)),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return PbsCard(
                      child: Text(
                        '아직 받은 칭찬이 없어요.\n매일 점검하고 선생님께 칭찬받아 보세요! 🌱',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                          height: 1.5,
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: list.take(5).map((p) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.sm),
                        child: PbsCard(
                          color: AppColors.studentGreenLight,
                          border: Border.all(
                              color: AppColors.studentGreen
                                  .withValues(alpha: 0.3)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('💬',
                                  style: TextStyle(fontSize: 18)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.message,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('M월 d일')
                                          .format(p.createdAt),
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
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

          const SectionHeader(title: '📈 최근 30일 점수 추이'),
          PbsCard(child: SizedBox(height: 200, child: _ScoreTrend(stats: statsAsync))),

          const SectionHeader(title: '🎯 카테고리 평균'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 200,
                child: Center(child: Text('오류: $e')),
              ),
              data: (s) => CategoryRadarChart(scores: s.categoryAverages),
            ),
          ),

          const SectionHeader(title: '🗓️ 참여 캘린더'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('오류: $e'),
              data: (s) {
                final byDate = <String, double>{
                  for (final c in s.last30)
                    KstDate.formatYmd(c.checkinDate): c.scorePct,
                };
                return MonthlyParticipationCalendar(scoresByDate: byDate);
              },
            ),
          ),

          const SectionHeader(title: '🧭 분석'),
          PbsCard(
            child: statsAsync.when(
              loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('오류: $e'),
              data: (s) {
                final delta = s.weekDelta;
                final deltaText = delta.abs() < 0.5
                    ? '지난주와 비슷한 수준이에요.'
                    : delta > 0
                        ? '지난주보다 ${delta.toStringAsFixed(1)}% 향상됐어요! 🎉'
                        : '지난주보다 ${(-delta).toStringAsFixed(1)}% 낮아요. 다시 도전!';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnalysisLine(
                      icon: '💪',
                      label: '가장 잘 지킨 규칙',
                      value: s.bestRuleText ?? '아직 데이터 부족',
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '🌱',
                      label: '더 신경 써야 할 규칙',
                      value: s.worstRuleText ?? '아직 데이터 부족',
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '📊',
                      label: '주간 변화',
                      value: deltaText,
                    ),
                    const SizedBox(height: 6),
                    _AnalysisLine(
                      icon: '🏅',
                      label: '최장 연속 기록',
                      value: '${s.longestStreak}일',
                    ),
                  ],
                );
              },
            ),
          ),

          // 알림 설정
          const SectionHeader(title: '🔔 알림 설정'),
          const _ReminderSettings(),

          // 계정 관리
          const SectionHeader(title: '⚙️ 계정 관리'),
          PbsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout_rounded,
                      color: AppColors.textSecondary),
                  title: Text(
                    '로그아웃',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () async {
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
                      fontSize: 14,
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
                  onTap: () => _confirmDeleteAccount(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '회원 탈퇴',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '정말 탈퇴하시겠어요?\n\n'
          '• 계정 정보, 자기점검 기록, 포인트, 뱃지가\n'
          '  모두 영구적으로 삭제됩니다.\n'
          '• 삭제된 데이터는 복구할 수 없습니다.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '탈퇴하기',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
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
      // 로딩을 먼저 닫는다 (상태 갱신으로 mounted가 false 되기 전에).
      if (context.mounted) Navigator.pop(context);
      ref.invalidate(profileProvider);
      if (context.mounted) {
        context.go('/welcome');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '회원 탈퇴가 완료되었습니다.',
              style: GoogleFonts.notoSansKr(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 로딩 닫기
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('탈퇴 실패',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Text(
            translateError(e),
            style: GoogleFonts.notoSansKr(fontSize: 13),
          ),
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
}

class _ReminderSettings extends StatefulWidget {
  const _ReminderSettings();

  @override
  State<_ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<_ReminderSettings> {
  bool _enabled = false;
  int _hour = 17;
  int _minute = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ReminderPrefs.load();
    if (!mounted) return;
    setState(() {
      _enabled = s.enabled;
      _hour = s.hour;
      _minute = s.minute;
      _loading = false;
    });
  }

  Future<void> _apply() =>
      ReminderPrefs.save(enabled: _enabled, hour: _hour, minute: _minute);

  Future<void> _onToggle(bool v) async {
    if (v) {
      final granted = await NotificationsService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '알림 권한이 꺼져 있어요. 휴대폰 설정 → 알림에서 자람 알림을 켜주세요.',
                style: GoogleFonts.notoSansKr(),
              ),
            ),
          );
        }
        return;
      }
    }
    setState(() => _enabled = v);
    await _apply();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PbsCard(
        child: SizedBox(
          height: 56,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return PbsCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: _onToggle,
            activeColor: AppColors.studentGreen,
            title: Text(
              '매일 점검 알림',
              style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              '정해진 시간에 자기점검을 잊지 않게 알려드려요',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
          if (_enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.access_time_rounded,
                  color: AppColors.textSecondary),
              title: Text(
                '알림 시간',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              trailing: Text(
                TimeOfDay(hour: _hour, minute: _minute).format(context),
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.studentGreen,
                ),
              ),
              onTap: _pickTime,
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalysisLine extends StatelessWidget {
  const _AnalysisLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreTrend extends StatelessWidget {
  const _ScoreTrend({required this.stats});
  final AsyncValue<StudentStats> stats;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (s) {
        if (s.last30.isEmpty) {
          return Center(
            child: Text(
              '아직 점검 기록이 없어요.',
              style: GoogleFonts.notoSansKr(color: AppColors.textTertiary),
            ),
          );
        }
        final sorted = [...s.last30]
          ..sort((a, b) => a.checkinDate.compareTo(b.checkinDate));
        final spots = <FlSpot>[
          for (var i = 0; i < sorted.length; i++)
            FlSpot(i.toDouble(), sorted[i].scorePct),
        ];
        return LineChart(
          LineChartData(
            minY: 0,
            maxY: 100,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 25,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.primary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PbsCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
