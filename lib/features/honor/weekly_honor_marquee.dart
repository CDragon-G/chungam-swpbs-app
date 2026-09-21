import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/supabase/supabase_client.dart';

/// 이 주의 명예 식집사 한 명 (반별 1위). 이름은 서버에서 가려져 온다.
class WeeklyHonorItem {
  const WeeklyHonorItem({required this.label, required this.isMe});

  /// '3-2 김*수'
  final String label;
  final bool isMe;

  factory WeeklyHonorItem.fromMap(Map<String, dynamic> m) => WeeklyHonorItem(
        label: (m['label'] as String?) ?? '',
        isMe: m['is_me'] == true,
      );
}

class WeeklyHonor {
  const WeeklyHonor({required this.isThisWeek, required this.items});

  /// 이번 주에 아직 아무도 점검하지 않았으면 지난주 결과가 온다.
  final bool isThisWeek;
  final List<WeeklyHonorItem> items;

  bool get hasMe => items.any((i) => i.isMe);

  factory WeeklyHonor.fromMap(Map<String, dynamic> m) => WeeklyHonor(
        isThisWeek: m['week'] == 'this',
        items: ((m['items'] as List?) ?? const [])
            .map((e) =>
                WeeklyHonorItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

final weeklyHonorProvider =
    FutureProvider.autoDispose<WeeklyHonor?>((ref) async {
  final res = await SupabaseService.client.rpc('weekly_honor_gardeners');
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) return null;
  return WeeklyHonor.fromMap(m);
});

/// 내 이번 주 점수 — 본인 것만 온다.
class MyWeeklyHonor {
  const MyWeeklyHonor({
    required this.joined,
    this.score = 0,
    this.rank = 0,
    this.daysDone = 0,
    this.avgPct = 0,
    this.praiseCnt = 0,
    this.gap = 0,
    this.isTop = false,
  });

  final bool joined; // 이번 주에 한 번이라도 점검했는가
  final int score;
  final int rank;
  final int daysDone;
  final int avgPct;
  final int praiseCnt;
  final int gap; // 우리 반 1위까지 남은 점수
  final bool isTop;

  factory MyWeeklyHonor.fromMap(Map<String, dynamic> m) => MyWeeklyHonor(
        joined: m['joined'] == true,
        score: (m['score'] as num?)?.toInt() ?? 0,
        rank: (m['rank'] as num?)?.toInt() ?? 0,
        daysDone: (m['days_done'] as num?)?.toInt() ?? 0,
        avgPct: (m['avg_pct'] as num?)?.toInt() ?? 0,
        praiseCnt: (m['praise_cnt'] as num?)?.toInt() ?? 0,
        gap: (m['gap'] as num?)?.toInt() ?? 0,
        isTop: m['is_top'] == true,
      );
}

final myWeeklyHonorProvider =
    FutureProvider.autoDispose<MyWeeklyHonor?>((ref) async {
  final res = await SupabaseService.client.rpc('my_weekly_honor');
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) return null;
  return MyWeeklyHonor.fromMap(m);
});

/// 🌿 학생 홈 상단에 흐르는 '이 주의 명예 식집사' 띠.
///
/// 반마다 한 명씩, 왼쪽에서 오른쪽으로 흐른다. 앱을 열어둔 동안 5분마다
/// 다시 계산해서 "실시간" 으로 바뀐다. 누르면 점수 기준과 내 점수를 보여준다.
class WeeklyHonorMarquee extends ConsumerStatefulWidget {
  const WeeklyHonorMarquee({super.key});

  @override
  ConsumerState<WeeklyHonorMarquee> createState() => _WeeklyHonorMarqueeState();
}

class _WeeklyHonorMarqueeState extends ConsumerState<WeeklyHonorMarquee> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) ref.invalidate(weeklyHonorProvider);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final honor = ref.watch(weeklyHonorProvider).value;
    if (honor == null || honor.items.isEmpty) return const SizedBox.shrink();

    final title = honor.isThisWeek ? '이 주의 명예 식집사' : '지난주 명예 식집사';

    return GestureDetector(
      onTap: () => showWeeklyHonorSheet(context),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFBBF7D0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 제목은 고정, 이름만 흐른다
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              height: double.infinity,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.studentGreen,
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(999)),
              ),
              child: Text(
                '🌿 $title',
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ),
            Expanded(
              child: _Marquee(
                children: [
                  for (final item in honor.items) _Chip(item: item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.item});
  final WeeklyHonorItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.label,
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: item.isMe ? FontWeight.w900 : FontWeight.w700,
              color:
                  item.isMe ? const Color(0xFFB45309) : AppColors.textPrimary,
            ),
          ),
          if (item.isMe) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('나!',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFB45309))),
            ),
          ],
          const SizedBox(width: 12),
          const Text('·',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

/// 왼쪽에서 오른쪽으로 끊김 없이 흐르는 띠.
///
/// 내용 한 벌의 너비를 재서, 화면을 채울 만큼 여러 벌 이어 붙인 뒤
/// 한 벌 너비만큼 오른쪽으로 밀었다가 되돌아온다. 되돌아오는 순간의 모습이
/// 시작 모습과 같아서 이음매가 보이지 않는다.
class _Marquee extends StatefulWidget {
  const _Marquee({required this.children});
  final List<Widget> children;

  /// 초당 이동 거리. 이름을 읽을 수 있을 만큼 느리게.
  static const double speed = 32;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  final _probe = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this);
  double _w = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _Marquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = _probe.currentContext?.findRenderObject() as RenderBox?;
    final w = box?.size.width ?? 0;
    if (w <= 0 || (w - _w).abs() < 0.5) return;
    setState(() => _w = w);
    _c
      ..duration = Duration(milliseconds: (w / _Marquee.speed * 1000).round())
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _copy({Key? key}) => Row(
        key: key,
        mainAxisSize: MainAxisSize.min,
        children: widget.children,
      );

  @override
  Widget build(BuildContext context) {
    // 움직임 줄이기를 켠 학생에게는 흐르지 않는 띠를 보여준다
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return LayoutBuilder(builder: (context, box) {
      final viewport = box.maxWidth;
      // 화면을 빈틈 없이 채우려면 몇 벌이 필요한가 (+1 은 흘러 들어올 몫)
      final copies = _w <= 0 ? 1 : (viewport / _w).ceil() + 1;

      final strip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _copy(key: _probe),
          for (var i = 1; i < copies; i++) _copy(),
        ],
      );

      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: (reduceMotion || _w <= 0)
              ? strip
              : AnimatedBuilder(
                  animation: _c,
                  // 좌 → 우: 한 벌 너비만큼 왼쪽에서 출발해 제자리로
                  builder: (_, child) => Transform.translate(
                    offset: Offset(-_w + _c.value * _w, 0),
                    child: child,
                  ),
                  child: strip,
                ),
        ),
      );
    });
  }
}

/// 점수 기준과 내 이번 주 점수.
void showWeeklyHonorSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _WeeklyHonorSheet(),
  );
}

class _WeeklyHonorSheet extends ConsumerWidget {
  const _WeeklyHonorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myWeeklyHonorProvider).value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.xl, AppSizes.lg, AppSizes.xl, AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('🌿 이 주의 명예 식집사',
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              '반마다 한 명씩, 이번 주를 가장 잘 가꾼 친구예요.\n'
              '월요일마다 새로 시작하니 누구나 될 수 있어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5, height: 1.6, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSizes.md),
            const _Rule(
                emoji: '📅',
                label: '꾸준함',
                pts: 40,
                desc: '이번 주 수업일에 빠짐없이 점검하기'),
            const _Rule(
                emoji: '✅', label: '실천', pts: 30, desc: '자기점검 O/X 평균 점수'),
            const _Rule(
                emoji: '💚',
                label: '칭찬',
                pts: 30,
                desc: '선생님께 받은 칭찬 1번에 10점 (3번까지)'),
            const SizedBox(height: AppSizes.md),
            if (me != null) _MyScore(me: me),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({
    required this.emoji,
    required this.label,
    required this.pts,
    required this.desc,
  });
  final String emoji;
  final String label;
  final int pts;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(label,
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Text(desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text('$pts점',
              maxLines: 1,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.studentGreen)),
        ],
      ),
    );
  }
}

class _MyScore extends StatelessWidget {
  const _MyScore({required this.me});
  final MyWeeklyHonor me;

  @override
  Widget build(BuildContext context) {
    final String headline;
    final String sub;
    if (!me.joined) {
      headline = '이번 주는 아직 점검 전이에요';
      sub = '오늘 자기점검을 하면 바로 후보가 돼요';
    } else if (me.isTop) {
      headline = '🎉 우리 반 명예 식집사예요!';
      sub = '이번 주 ${me.score}점 · 점검 ${me.daysDone}일 · 칭찬 ${me.praiseCnt}번';
    } else {
      // 등수는 보여주지 않는다. "우리 반 23등" 은 하위권 학생에게 벌처럼 읽힌다.
      // 1등과의 차이도 가까울 때만 — 멀면 따라잡을 마음보다 포기가 먼저 온다.
      headline = '이번 주 ${me.score}점';
      sub = (me.gap > 0 && me.gap <= 20)
          ? '명예 식집사까지 ${me.gap}점! 조금만 더 가꿔봐요'
          : '점검 ${me.daysDone}일 · 칭찬 ${me.praiseCnt}번 · 매일 조금씩 자라고 있어요';
    }

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: me.isTop ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
