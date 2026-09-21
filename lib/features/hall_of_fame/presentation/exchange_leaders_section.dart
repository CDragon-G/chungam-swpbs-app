import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/widgets/pbs_card.dart';

class ExchangeLeader {
  const ExchangeLeader({
    required this.label,
    required this.count,
    required this.points,
    required this.isMe,
  });

  /// 서버에서 가운데를 가린 이름 ('2-3 김*수')
  final String label;
  final int count;
  final int points;
  final bool isMe;

  factory ExchangeLeader.fromMap(Map<String, dynamic> m) => ExchangeLeader(
        label: (m['label'] as String?) ?? '',
        count: (m['count'] as num?)?.toInt() ?? 0,
        points: (m['points'] as num?)?.toInt() ?? 0,
        isMe: m['is_me'] == true,
      );
}

/// 🛍️ 강화물을 가장 많이 받아 간 학생 (최근 90일, 수령 완료 기준).
final exchangeLeadersProvider =
    FutureProvider.autoDispose<List<ExchangeLeader>>((ref) async {
  try {
    final res = await SupabaseService.client
        .rpc('exchange_leaders', params: {'p_limit': 3, 'p_days': 90});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['ok'] != true) return const [];
    return ((m['items'] as List?) ?? const [])
        .map((e) => ExchangeLeader.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return const []; // 서버에 아직 064 가 없으면 이 칸을 숨긴다
  }
});

/// 명예의 전당 — 🛍️ 강화물 교환왕.
class ExchangeLeadersSection extends ConsumerWidget {
  const ExchangeLeadersSection({super.key});

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(exchangeLeadersProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '🛍️ 강화물 교환왕'),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '최근 90일 동안 강화물을 가장 많이 받아 간 친구들이에요.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
                fontSize: 11.5, color: AppColors.textTertiary),
          ),
        ),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PbsCard(
              color: items[i].isMe ? const Color(0xFFF0FDF4) : null,
              border: items[i].isMe
                  ? Border.all(color: const Color(0xFF86EFAC), width: 1.4)
                  : null,
              child: Row(
                children: [
                  Text(i < _medals.length ? _medals[i] : '🎁',
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      items[i].isMe ? '${items[i].label} (나)' : items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${items[i].count}개',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.studentGreen)),
                      Text('${items[i].points}P 사용',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 10.5, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
