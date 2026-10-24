import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../school/providers/school_provider.dart';

/// 📣 이벤트 공지 — 공지에 이미지 · 기간 · 색 · 연결 강화물을 붙인 홍보 (073).
///
/// 예: '따뜻한 등굣길 캠페인' — 11월 17일부터 등굣길에서 어묵을 나눠주고,
/// 자람 포인트로 교환할 수 있게 한다. 기간 전부터 홈에 배너로 띄워 기대감을 만든다.
class SchoolEvent {
  const SchoolEvent({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.imageUrl,
    this.start,
    this.end,
    this.theme = EventTheme.warm,
    this.itemId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? imageUrl;
  final DateTime? start; // 행사 시작일 (D-day 기준)
  final DateTime? end; // 행사 마지막 날 — 지나면 배너가 내려간다
  final EventTheme theme;
  final String? itemId; // 연결한 강화물 (교환소로 바로 가기)

  /// 공지 한 줄(map)이 이벤트면 SchoolEvent 로, 아니면 null.
  static SchoolEvent? fromNotice(Map<String, dynamic> m) {
    if (m['kind'] != 'event') return null;
    DateTime? d(String k) {
      final v = m[k];
      return v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    }

    return SchoolEvent(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      body: (m['body'] as String?) ?? '',
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      imageUrl: (m['image_url'] as String?)?.trim().isNotEmpty == true
          ? (m['image_url'] as String).trim()
          : null,
      start: d('event_start'),
      end: d('event_end'),
      theme: EventTheme.of(m['theme'] as String?),
      itemId: m['item_id'] as String?,
    );
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static bool _isEmoji(int r) =>
      (r >= 0x1F000 && r <= 0x1FAFF) ||
      (r >= 0x2600 && r <= 0x27BF) ||
      (r >= 0x2B00 && r <= 0x2BFF);

  /// 제목 맨 앞의 이모지 ('🍢 따뜻한 등굣길' → '🍢'), 없으면 null
  String? get leadingEmoji {
    final t = title.trim();
    if (t.isEmpty || !_isEmoji(t.runes.first)) return null;
    final sp = t.indexOf(' ');
    return sp < 0 ? t : t.substring(0, sp);
  }

  /// 제목에서 맨 앞 이모지를 뺀 것 (배너 동그라미에 이모지가 따로 있을 때)
  String get plainTitle {
    final e = leadingEmoji;
    return e == null ? title.trim() : title.trim().substring(e.length).trim();
  }

  /// 배너 · 구름에 쓰는 이모지 — 제목에 있으면 그것, 없으면 테마 이모지
  String get emoji => leadingEmoji ?? theme.emoji;

  /// 오늘(한국 시간) 홈에 띄울 이벤트인가 — 마지막 날까지.
  bool get isActive {
    final today = _day(KstDate.today());
    return end == null || !today.isAfter(_day(end!));
  }

  /// 'D-3' · 'D-DAY' · '진행 중' · null(날짜 없음)
  String? get dDay {
    if (start == null) return end == null ? null : '진행 중';
    final today = _day(KstDate.today());
    final diff = _day(start!).difference(today).inDays;
    if (diff > 0) return 'D-$diff';
    if (diff == 0) return 'D-DAY';
    return '진행 중';
  }

  /// '11월 17일(월) ~ 12월 19일(금)'
  String? get periodText {
    final f = DateFormat('M월 d일(E)', 'ko');
    if (start != null && end != null)
      return '${f.format(start!)} ~ ${f.format(end!)}';
    if (start != null) return '${f.format(start!)}부터';
    if (end != null) return '${f.format(end!)}까지';
    return null;
  }
}

/// 이벤트 배너 색 묶음. 이미지가 없어도 홍보물처럼 보이게 한다.
class EventTheme {
  const EventTheme._(this.key, this.label, this.emoji, this.colors, this.ink);

  final String key;
  final String label;
  final String emoji;
  final List<Color> colors; // 그라데이션 (왼쪽 위 → 오른쪽 아래)
  final Color ink; // 배너 위 강조 글자색

  static const warm = EventTheme._('warm', '따뜻한', '🍢',
      [Color(0xFFFF9A3C), Color(0xFFE8452C)], Color(0xFFFFF4D6));
  static const festive = EventTheme._('festive', '축제', '🎉',
      [Color(0xFF9B6BFF), Color(0xFFE5487F)], Color(0xFFFFE9F3));
  static const green = EventTheme._('green', '자람', '🌱',
      [Color(0xFF34C17B), Color(0xFF0E7C66)], Color(0xFFE6FFF2));
  static const winter = EventTheme._('winter', '겨울', '❄️',
      [Color(0xFF4F8DF7), Color(0xFF233A8F)], Color(0xFFE3EDFF));

  static const all = [warm, festive, green, winter];

  static EventTheme of(String? key) =>
      all.firstWhere((t) => t.key == key, orElse: () => warm);

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      );
}

/// 지금 홈에 띄울 이벤트들 (최신 순).
final activeEventsProvider = Provider<List<SchoolEvent>>((ref) {
  final rows = ref.watch(announcementsProvider).value ?? const [];
  return rows
      .map(SchoolEvent.fromNotice)
      .whereType<SchoolEvent>()
      .where((e) => e.isActive)
      .toList();
});

/// 이벤트 배너 — 홈의 공지 자리에 공지와 번갈아 뜬다. 누르면 자세히 보기.
class EventBanner extends StatelessWidget {
  const EventBanner({super.key, required this.event, required this.onTap});
  final SchoolEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = event.theme;
    final dday = event.dDay;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.only(left: 4, right: 10),
        decoration: BoxDecoration(
          gradient: t.gradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: t.colors.last.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // 이미지가 있으면 동그란 썸네일, 없으면 테마 이모지
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: event.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: event.imageUrl!,
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Text(event.emoji,
                          style: const TextStyle(fontSize: 16)),
                    )
                  : Text(event.emoji, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 7),
            if (dday != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: t.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  dday,
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: t.colors.last,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                event.imageUrl == null ? event.plainTitle : event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Color(0x33000000), blurRadius: 3),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// 홈의 공지 자리: 이벤트가 있으면 이벤트 배너와 최근 공지를 6초마다 번갈아 보여준다.
class NoticeSlot extends StatefulWidget {
  const NoticeSlot({
    super.key,
    required this.events,
    required this.notice,
    required this.onEvent,
  });

  final List<SchoolEvent> events;

  /// 최근 공지 배너 (이벤트가 아닌 공지가 있을 때)
  final Widget? notice;
  final void Function(SchoolEvent) onEvent;

  @override
  State<NoticeSlot> createState() => _NoticeSlotState();
}

class _NoticeSlotState extends State<NoticeSlot> {
  int _i = 0;
  late final Stream<int> _tick =
      Stream.periodic(const Duration(seconds: 6), (n) => n);

  List<Widget> _slides() => [
        for (final e in widget.events)
          EventBanner(
              key: ValueKey('ev-${e.id}'),
              event: e,
              onTap: () => widget.onEvent(e)),
        if (widget.notice != null)
          KeyedSubtree(key: const ValueKey('notice'), child: widget.notice!),
      ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _tick,
      builder: (context, snap) {
        final slides = _slides();
        if (slides.isEmpty) return const SizedBox.shrink();
        if (snap.hasData) _i = snap.data! + 1;
        final child = slides[_i % slides.length];
        if (slides.length == 1 || MediaQuery.of(context).disableAnimations) {
          return slides.first;
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                  .animate(a),
              child: c,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// 홈에 들어올 때 이벤트 팝업 — 이벤트마다 하루 한 번, 한 번에 하나만.
/// 같은 날 다시 홈에 와도 뜨지 않는다. 띄웠으면 true.
Future<bool> maybeShowEventPopup(
  BuildContext context,
  WidgetRef ref, {
  required bool isTeacher,
}) async {
  final events = ref.read(activeEventsProvider);
  if (events.isEmpty) return false;
  final prefs = await SharedPreferences.getInstance();
  final today = KstDate.formatYmd(KstDate.today());
  for (final e in events) {
    final key = 'event_popup_${e.id}';
    if (prefs.getString(key) == today) continue;
    await prefs.setString(key, today);
    if (!context.mounted) return false;
    await showEventSheet(context, e, isTeacher: isTeacher);
    return true;
  }
  return false;
}

/// 이벤트 자세히 보기 (팝업 · 배너 탭 공용).
Future<void> showEventSheet(
  BuildContext context,
  SchoolEvent e, {
  required bool isTeacher,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _EventDialog(event: e, isTeacher: isTeacher),
  );
}

class _EventDialog extends StatelessWidget {
  const _EventDialog({required this.event, required this.isTeacher});
  final SchoolEvent event;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final t = event.theme;
    final period = event.periodText;
    final dday = event.dDay;
    final maxH = MediaQuery.sizeOf(context).height * 0.82;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 머리: 이미지 또는 테마 포스터 ──
              Stack(
                children: [
                  if (event.imageUrl != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH * 0.48),
                      child: CachedNetworkImage(
                        imageUrl: event.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _Poster(event: event),
                        errorWidget: (_, __, ___) => _Poster(event: event),
                      ),
                    )
                  else
                    _Poster(event: event),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      iconSize: 20,
                      onPressed: () => Navigator.pop(context),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (period != null || dday != null)
                        Row(
                          children: [
                            if (dday != null)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: t.gradient,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(dday,
                                    maxLines: 1,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white)),
                              ),
                            if (period != null)
                              Expanded(
                                child: Text(period,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary)),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Text(event.title,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      Text(event.body,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 13.5,
                              height: 1.65,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              // ── 아래: 교환소로 가기 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (event.itemId != null)
                      SizedBox(
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: t.gradient,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.go(isTeacher
                                  ? '/teacher/store'
                                  : '/student/store');
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              isTeacher ? '교환소에서 보기' : '교환소에서 신청하기',
                              maxLines: 1,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 15, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('닫기',
                          maxLines: 1,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 이미지가 없을 때의 포스터 — 테마 그라데이션 + 큰 이모지 + D-day.
class _Poster extends StatelessWidget {
  const _Poster({required this.event});
  final SchoolEvent event;

  @override
  Widget build(BuildContext context) {
    final t = event.theme;
    return Container(
      height: 168,
      decoration: BoxDecoration(gradient: t.gradient),
      child: Stack(
        children: [
          // 배경 장식 동그라미
          Positioned(
            right: -30,
            top: -40,
            child: _Dot(size: 150, color: Colors.white.withValues(alpha: 0.12)),
          ),
          Positioned(
            left: -24,
            bottom: -50,
            child: _Dot(size: 120, color: Colors.white.withValues(alpha: 0.10)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.emoji, style: const TextStyle(fontSize: 58)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'SCHOOL EVENT',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: t.ink,
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
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
