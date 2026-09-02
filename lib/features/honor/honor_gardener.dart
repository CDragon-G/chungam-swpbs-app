import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/widgets/pbs_card.dart';

/// 🌿 명예 식집사 — 2주에 한 명.
/// 지난 2주 동안 자기점검을 가장 꾸준히 한 학생에게 500P.
class HonorStatus {
  const HonorStatus({
    required this.ok,
    this.winner,
    this.winnerDays = 0,
    this.winnerAvg = 0,
    this.isMe = false,
    this.pending = false,
    this.secondsLeft = 0,
  });

  final bool ok;
  final String? winner;
  final int winnerDays;
  final int winnerAvg;
  final bool isMe;

  /// 지난 회차 선정이 아직 안 됐는가 (관리자에게 알림).
  final bool pending;

  /// 다음 선정까지 남은 초.
  final int secondsLeft;

  static const none = HonorStatus(ok: false);

  factory HonorStatus.fromMap(Map<String, dynamic> m) => HonorStatus(
        ok: (m['ok'] as bool?) ?? false,
        winner: m['winner'] as String?,
        winnerDays: (m['winner_days'] as num?)?.toInt() ?? 0,
        winnerAvg: (m['winner_avg'] as num?)?.toInt() ?? 0,
        isMe: (m['is_me'] as bool?) ?? false,
        pending: (m['pending'] as bool?) ?? false,
        secondsLeft: (m['seconds_left'] as num?)?.toInt() ?? 0,
      );
}

final honorStatusProvider = FutureProvider<HonorStatus>((ref) async {
  try {
    final res = await SupabaseService.client.rpc('honor_gardener_status');
    return HonorStatus.fromMap(Map<String, dynamic>.from(res as Map));
  } catch (_) {
    return HonorStatus.none;
  }
});

/// 남은 시간을 '3일 04:12' 처럼 사람이 읽는 형태로.
String formatLeft(int seconds) {
  if (seconds <= 0) return '곧 선정';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '$d일 ${h.toString().padLeft(2, '0')}시간';
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 홈 상단에 얹는 카드 — 현재 명예 식집사와 다음 선정까지 남은 시간.
/// 초 단위로 줄어드는 걸 보여주려고 1분마다 스스로 다시 그린다.
class HonorGardenerCard extends ConsumerStatefulWidget {
  const HonorGardenerCard({super.key, this.isAdmin = false});
  final bool isAdmin;

  @override
  ConsumerState<HonorGardenerCard> createState() => _HonorCardState();
}

class _HonorCardState extends ConsumerState<HonorGardenerCard> {
  Timer? _tick;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _elapsed += 60);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _select() async {
    try {
      final res =
          await SupabaseService.client.rpc('select_honor_gardener');
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) throw StateError(m['error'] as String? ?? '실패');
      ref.invalidate(honorStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m['name']} 학생이 명예 식집사로 선정됐어요! (500P)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(honorStatusProvider).value;
    if (st == null || !st.ok) return const SizedBox.shrink();

    final left = (st.secondsLeft - _elapsed).clamp(0, 1 << 31);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: PbsCard(
        color: const Color(0xFFF3F9F0),
        border: Border.all(color: AppColors.studentGreen.withValues(alpha: 0.3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌿', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('명예 식집사',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.studentGreen)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.studentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('다음 선정까지 ${formatLeft(left)}',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.studentGreen)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (st.winner != null)
              Text(
                st.isMe
                    ? '이번 회차 명예 식집사는 나예요! 🎉 500P를 받았어요.'
                    : '이번 회차 명예 식집사는 ${st.winner} 학생이에요. '
                        '(${st.winnerDays}일 점검 · 평균 ${st.winnerAvg}점)',
                style: GoogleFonts.notoSansKr(fontSize: 12.5, height: 1.5),
              )
            else
              Text(
                '2주 동안 자기점검을 가장 꾸준히 한 학생 한 명에게 500P를 드려요.',
                style: GoogleFonts.notoSansKr(fontSize: 12.5, height: 1.5),
              ),
            if (widget.isAdmin && st.pending) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _select,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.studentGreen,
                    side: BorderSide(
                        color:
                            AppColors.studentGreen.withValues(alpha: 0.5)),
                  ),
                  icon: const Icon(Icons.emoji_events_rounded, size: 18),
                  label: Text('지난 회차 명예 식집사 선정하기',
                      style:
                          GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
