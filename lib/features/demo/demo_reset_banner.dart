import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/providers/profile_provider.dart';
import '../../shared/widgets/pbs_card.dart';
import '../school/providers/school_provider.dart';

/// 🎪 체험 학교(엑스포 부스)에서만 보이는 초기화 배너.
///
/// 관람객 한 팀이 체험을 마치면 부스 선생님이 누른다.
///   · 우리 반 초기화 — 이 선생님의 담임 반(= 부스 세트 하나)만 처음으로 돌린다.
///                     다른 세트에서 체험 중인 관람객 기록은 그대로 둔다.
///   · 학교 전체      — 세 세트를 한꺼번에.
/// 오늘 기록이 지워지고 예시 데이터(최근 14일 점검, 칭찬, 함께 키우기, K-ODR)가 다시 채워진다.
/// 학생 태블릿은 30초 안에 저절로 새로 고친다.
///
/// 서버가 체험 학교인지 다시 확인하므로, 실제 학교에서는 불러도 아무 일도 없다.
class DemoResetBanner extends ConsumerStatefulWidget {
  const DemoResetBanner({super.key});

  @override
  ConsumerState<DemoResetBanner> createState() => _DemoResetBannerState();
}

class _DemoResetBannerState extends ConsumerState<DemoResetBanner> {
  bool _busy = false;

  Future<void> _reset({required bool wholeSchool}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            wholeSchool ? '학교 전체를 처음으로 돌릴까요?' : '우리 반을 처음으로 돌릴까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          wholeSchool
              ? '세 세트 모두의 오늘 점검 · 칭찬 · 교환 · 편지가 지워지고\n'
                  '예시 데이터가 다시 채워집니다.\n\n'
                  '다른 세트에서 체험 중인 관람객이 있으면 그 기록도 사라져요.'
              : '이 태블릿과 짝인 학생의 오늘 점검 · 칭찬 · 교환 · 편지가 지워지고\n'
                  '예시 데이터가 다시 채워집니다.\n\n'
                  '다른 세트는 그대로예요. 학생 태블릿은 30초 안에 따라와요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('초기화',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await SupabaseService.client.rpc(
        'reset_demo_school',
        params: {'p_scope': wholeSchool ? 'all' : 'class'},
      );
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) {
        throw StateError(m['error'] as String? ?? '초기화하지 못했어요');
      }
      // 프로필을 다시 읽으면 그 아래의 거의 모든 화면 데이터가 따라서 새로 고쳐진다
      ref.invalidate(profileProvider);
      ref.invalidate(schoolProvider);
      if (mounted) {
        final scope = m['scope'] == 'class' ? '${m['class']}반' : '학교 전체';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$scope 처음 상태로 되돌렸어요'
                ' · 점검 예시 ${m['checkins_seeded']}건'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isDemoSchoolProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PbsCard(
        color: const Color(0xFFF5F3FF),
        border: Border.all(color: const Color(0xFFC4B5FD)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('🎪', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('체험용 학교',
                          maxLines: 1,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF5B21B6))),
                      Text('관람객이 바뀔 때마다 눌러주세요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11.5,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _busy ? null : () => _reset(wholeSchool: false),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED)),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text('우리 반 초기화',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : () => _reset(wholeSchool: true),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF5B21B6)),
                  child: Text('학교 전체',
                      maxLines: 1,
                      style:
                          GoogleFonts.notoSansKr(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
