import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/widgets/flame_streak.dart';
import '../../../shared/widgets/pbs_card.dart';

class StreakLeader {
  const StreakLeader({
    required this.label,
    required this.days,
    required this.best,
    required this.isMe,
  });

  /// 서버에서 가운데를 가린 이름 ('2-3 김*수' 또는 반 순위는 '김*수')
  final String label;
  final int days;
  final int best;
  final bool isMe;

  factory StreakLeader.fromMap(Map<String, dynamic> m) => StreakLeader(
        label: (m['label'] as String?) ?? '',
        days: (m['days'] as num?)?.toInt() ?? 0,
        best: (m['best'] as num?)?.toInt() ?? 0,
        isMe: m['is_me'] == true,
      );
}

class StreakLeaders {
  const StreakLeaders({
    this.schoolTop = const [],
    this.classTop = const [],
    this.classLabel,
  });

  final List<StreakLeader> schoolTop;
  final List<StreakLeader> classTop;
  final String? classLabel;
}

/// 🔥 지금 이어지고 있는 연속 참여 순위.
final streakLeadersProvider =
    FutureProvider.autoDispose<StreakLeaders?>((ref) async {
  try {
    final res = await SupabaseService.client
        .rpc('streak_leaders', params: {'p_limit': 10});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) return null;
    List<StreakLeader> list(Object? v) => ((v as List?) ?? const [])
        .map((e) => StreakLeader.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return StreakLeaders(
      schoolTop: list(m['school_top']),
      classTop: list(m['class_top']),
      classLabel: m['class_label'] as String?,
    );
  } catch (_) {
    return null; // 서버에 아직 063 이 없으면 이 칸을 숨긴다
  }
});

/// 명예의 전당 — 🔥 연속 참여 불꽃.
class StreakLeadersSection extends ConsumerWidget {
  const StreakLeadersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(streakLeadersProvider).value;
    if (data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '🔥 연속 참여 불꽃'),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '수업일 기준이에요. 주말·공휴일·방학은 건너뛰어요.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
                fontSize: 11.5, color: AppColors.textTertiary),
          ),
        ),
        if (data.classTop.isNotEmpty && data.classLabel != null) ...[
          _SubTitle('우리 반 (${data.classLabel})'),
          for (var i = 0; i < data.classTop.length; i++)
            _LeaderRow(rank: i + 1, leader: data.classTop[i]),
          const SizedBox(height: 8),
        ],
        const _SubTitle('전교'),
        if (data.schoolTop.isEmpty)
          PbsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '아직 3일 이상 이어가는 친구가 없어요.\n첫 불꽃의 주인공이 되어볼까요? 🔥',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (var i = 0; i < data.schoolTop.length; i++)
            _LeaderRow(rank: i + 1, leader: data.schoolTop[i]),
        const SizedBox(height: 4),
        Text(
          '5일 · 10일 · 20일 · 50일 · 100일을 이으면 불꽃 뱃지를 받아요',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
              fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textSecondary)),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.leader});
  final int rank;
  final StreakLeader leader;

  @override
  Widget build(BuildContext context) {
    final tier = FlameTier.of(leader.days);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PbsCard(
        color: leader.isMe ? const Color(0xFFFFF7ED) : null,
        border: leader.isMe
            ? Border.all(color: const Color(0xFFFDBA74), width: 1.4)
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: rank <= 3
                          ? const Color(0xFFEA580C)
                          : AppColors.textTertiary)),
            ),
            const SizedBox(width: 6),
            if (tier != null) FlameIcon(tier: tier, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leader.isMe ? '${leader.label} (나)' : leader.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  if (tier != null)
                    Text(
                      tier.name,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tier.text),
                    ),
                ],
              ),
            ),
            Text(
              '${leader.days}일',
              style: GoogleFonts.notoSansKr(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: tier?.text ?? AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
