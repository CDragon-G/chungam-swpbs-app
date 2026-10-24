import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../notice/school_event.dart';
import 'live_feed.dart';

/// ☁️ 하늘을 흐르는 구름 소식.
///
/// 오른쪽에서 들어와 왼쪽으로 천천히 흘러간다. 구름마다 소식 하나 —
/// 방금 교환한 강화물, 오늘 교환 · 점검 · 칭찬 수, 명예 식집사 · 명예의 전당 1위.
/// 방금 일어난 일은 줄 맨 앞으로 끼워 넣어 바로 다음 구름에 싣는다.
///
/// 터치를 받지 않는다 (뒤의 메뉴 · 당겨서 새로고침을 막지 않게).
/// 60초마다 서버 소식을 다시 받는다 (서버도 학교마다 60초 보관).
class FeedCloudSky extends ConsumerStatefulWidget {
  const FeedCloudSky({
    super.key,
    required this.lanes,
    required this.teacher,
    this.scale = 1,
  });

  /// 구름이 지나가는 줄 수 (1~2). 화면 높이에 맞춰 홈이 정한다.
  final int lanes;
  final bool teacher;
  final double scale;

  /// 한 줄의 높이 (홈이 자리를 계산할 때도 쓴다)
  static double laneHeight(double scale) => 64 * scale;

  @override
  ConsumerState<FeedCloudSky> createState() => _FeedCloudSkyState();
}

class _Cloud {
  _Cloud({
    required this.note,
    required this.lane,
    required this.x,
    required this.w,
    required this.speed,
    required this.phase,
  });
  final CloudNote note;
  final int lane;
  double x;
  final double w;
  final double speed;
  final double phase;
}

class _FeedCloudSkyState extends ConsumerState<FeedCloudSky>
    with SingleTickerProviderStateMixin {
  final _rand = math.Random();
  late final Ticker _ticker = createTicker(_onTick);
  Timer? _refresh;
  Duration _last = Duration.zero;
  double _t = 0; // 흐른 시간(초) — 구름이 살짝 위아래로 떠다니는 데 쓴다
  double _width = 0;

  final List<_Cloud> _clouds = [];
  List<CloudNote> _notes = const [];
  final List<CloudNote> _urgent = []; // 방금 생긴 소식 — 다음 구름에 먼저
  final Set<String> _seen = {};
  int _cursor = 0;
  final List<double> _laneGap = [0, 0];
  TextScaler _scaler = TextScaler.noScaling;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      // 앱이 화면에 떠 있을 때만 (백그라운드에서는 서버를 부르지 않는다)
      final live = WidgetsBinding.instance.lifecycleState;
      if (mounted && (live == null || live == AppLifecycleState.resumed)) {
        ref.invalidate(liveFeedProvider);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  // ── 소식 줄 ──────────────────────────────────────────────

  void _sync(List<CloudNote> notes) {
    final first = _seen.isEmpty;
    for (final n in notes) {
      if (_seen.add(n.key) && n.fresh && !first) _urgent.add(n);
    }
    // 처음 열었을 때는 방금 일어난 일부터 보여준다
    if (first) _urgent.addAll(notes.where((n) => n.fresh));
    _notes = notes;
  }

  CloudNote? _nextNote() {
    final onScreen = _clouds.map((c) => c.note.key).toSet();
    while (_urgent.isNotEmpty) {
      final n = _urgent.removeAt(0);
      if (!onScreen.contains(n.key)) return n;
    }
    if (_notes.isEmpty) return null;
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[_cursor++ % _notes.length];
      if (!onScreen.contains(n.key)) return n;
    }
    return null;
  }

  // ── 구름 크기 ────────────────────────────────────────────

  // 매 프레임 다시 만들지 않도록 크기가 바뀔 때만 만든다
  double? _styleScale;
  late TextStyle _topStyle;
  late TextStyle _mainStyle;

  void _ensureStyles() {
    if (_styleScale == widget.scale) return;
    _styleScale = widget.scale;
    _topStyle = GoogleFonts.notoSansKr(
        fontSize: 10.5 * widget.scale,
        fontWeight: FontWeight.w800,
        height: 1.25);
    _mainStyle = GoogleFonts.notoSansKr(
        fontSize: 13 * widget.scale, fontWeight: FontWeight.w900, height: 1.3);
  }

  double _measure(CloudNote n) {
    double w(String s, TextStyle st) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
      )..layout();
      return tp.width;
    }

    // 실제 구름은 글씨에 맞춰 스스로 넓어진다. 이 값은 간격 · 화면 밖 판정용이라 넉넉하게
    final text = math.max(w(n.top, _topStyle), w(n.main, _mainStyle));
    return text * 1.15 + 56 * widget.scale;
  }

  // ── 움직임 ───────────────────────────────────────────────

  void _spawn(int lane, {double? x}) {
    final note = _nextNote();
    if (note == null) return;
    final w = _measure(note);
    _clouds.add(_Cloud(
      note: note,
      lane: lane,
      x: x ?? _width + 4,
      w: w,
      speed: (22 + _rand.nextDouble() * 8) * widget.scale,
      phase: _rand.nextDouble() * math.pi * 2,
    ));
    _laneGap[lane] = (50 + _rand.nextDouble() * 90) * widget.scale;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;
    for (final c in _clouds) {
      c.x -= c.speed * dt;
    }
    _clouds.removeWhere((c) => c.x + c.w < -8);

    for (var lane = 0; lane < widget.lanes; lane++) {
      _Cloud? last;
      for (final c in _clouds) {
        if (c.lane == lane && (last == null || c.x > last.x)) last = c;
      }
      if (last == null || last.x + last.w < _width - _laneGap[lane]) {
        _spawn(lane);
      }
    }
    if (_clouds.isEmpty && _notes.isEmpty) {
      _ticker.stop();
      _last = Duration.zero;
    }
    setState(() {});
  }

  /// 처음 열었을 때 하늘이 비어 있지 않게, 화면 안쪽에 미리 한두 개 띄운다.
  void _seed() {
    if (_clouds.isNotEmpty || _width <= 0) return;
    _spawn(0, x: _width * 0.30);
    if (widget.lanes > 1) _spawn(1, x: _width * 0.78);
  }

  @override
  Widget build(BuildContext context) {
    _ensureStyles();
    final feed = ref.watch(liveFeedProvider).value;
    final events = ref.watch(activeEventsProvider);
    _sync(CloudNotes.build(
      feed: feed,
      events: events,
      now: DateTime.now(),
      teacher: widget.teacher,
    ));

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final laneH = FeedCloudSky.laneHeight(widget.scale);
    _scaler = MediaQuery.textScalerOf(context);

    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth;
        if (_notes.isEmpty) return const SizedBox.shrink();

        // 움직임 줄이기를 켠 사용자: 가운데 구름 하나가 6초마다 소식을 바꾼다
        if (reduceMotion) {
          return Align(
            alignment: Alignment.topCenter,
            child: _StillCloud(
                notes: _notes,
                scale: widget.scale,
                topStyle: _topStyle,
                mainStyle: _mainStyle),
          );
        }

        if (!_ticker.isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _ticker.isActive) return;
            _seed();
            _ticker.start();
          });
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final c in _clouds)
              Positioned(
                left: c.x,
                top: c.lane * laneH +
                    (c.lane.isOdd ? 4 * widget.scale : 0) +
                    math.sin(_t * 0.9 + c.phase) * 2.2 * widget.scale,
                child: CloudBubble(
                  note: c.note,
                  height: laneH - 4 * widget.scale,
                  scale: widget.scale,
                  topStyle: _topStyle,
                  mainStyle: _mainStyle,
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// 구름 한 개 — 뭉게구름 모양 위에 두 줄 글씨.
class CloudBubble extends StatelessWidget {
  const CloudBubble({
    super.key,
    required this.note,
    required this.height,
    required this.scale,
    required this.topStyle,
    required this.mainStyle,
  });

  final CloudNote note;
  final double height;
  final double scale;
  final TextStyle topStyle;
  final TextStyle mainStyle;

  static Color _ink(CloudTone t) => switch (t) {
        CloudTone.exchange => const Color(0xFFD9480F),
        CloudTone.honor => const Color(0xFFB7791F),
        CloudTone.fame => const Color(0xFF6B46C1),
        CloudTone.promo => const Color(0xFFE03131),
        CloudTone.plain => const Color(0xFF2F855A),
      };

  @override
  Widget build(BuildContext context) {
    final promo = note.tone == CloudTone.promo;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _CloudPainter(
          fill: promo
              ? const Color(0xFFFFF6EE).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.95),
        ),
        child: Padding(
          // 구름 몸통(아래쪽 70%) 가운데에 글씨
          padding: EdgeInsets.fromLTRB(
              23 * scale, height * 0.30, 23 * scale, 2 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(note.top,
                  maxLines: 1,
                  softWrap: false,
                  style: topStyle.copyWith(color: _ink(note.tone))),
              Text(note.main,
                  maxLines: 1,
                  softWrap: false,
                  style: mainStyle.copyWith(color: const Color(0xFF1F2937))),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  const _CloudPainter({required this.fill});
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 몸통(둥근 사각형) + 위쪽 뭉게뭉게 (겹친 원은 하나로 칠해진다)
    final p = Path()
      ..addRRect(RRect.fromLTRBR(0, h * 0.30, w, h, Radius.circular(h * 0.35)))
      ..addOval(
          Rect.fromCircle(center: Offset(w * 0.20, h * 0.42), radius: h * 0.27))
      ..addOval(
          Rect.fromCircle(center: Offset(w * 0.40, h * 0.30), radius: h * 0.34))
      ..addOval(
          Rect.fromCircle(center: Offset(w * 0.62, h * 0.33), radius: h * 0.30))
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.82, h * 0.46), radius: h * 0.24));
    canvas.drawShadow(p, const Color(0x55000000), 3, false);
    canvas.drawPath(p, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) => old.fill != fill;
}

/// 움직임 줄이기용 — 제자리에서 소식만 바뀌는 구름.
class _StillCloud extends StatefulWidget {
  const _StillCloud({
    required this.notes,
    required this.scale,
    required this.topStyle,
    required this.mainStyle,
  });
  final List<CloudNote> notes;
  final double scale;
  final TextStyle topStyle;
  final TextStyle mainStyle;

  @override
  State<_StillCloud> createState() => _StillCloudState();
}

class _StillCloudState extends State<_StillCloud> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notes[_i % widget.notes.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: CloudBubble(
        key: ValueKey(n.key),
        note: n,
        height: FeedCloudSky.laneHeight(widget.scale) - 4 * widget.scale,
        scale: widget.scale,
        topStyle: widget.topStyle,
        mainStyle: widget.mainStyle,
      ),
    );
  }
}
