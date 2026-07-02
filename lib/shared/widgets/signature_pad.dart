import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';

/// 보호자 서명 다이얼로그.
/// 손가락으로 서명 → PNG(base64) 문자열 반환, 취소하면 null.
/// 외부 패키지 없이 CustomPaint로 구현.
class SignaturePadDialog {
  SignaturePadDialog._();

  static Future<String?> show(BuildContext context,
      {String title = '보호자 서명'}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SignatureDialog(title: title),
    );
  }
}

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog({required this.title});
  final String title;

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final List<List<Offset>> _strokes = [];
  Size _padSize = const Size(1, 1);
  bool _exporting = false;

  bool get _isEmpty =>
      _strokes.isEmpty || _strokes.every((s) => s.length < 2);

  void _start(Offset p) => setState(() => _strokes.add([p]));

  void _move(Offset p) {
    if (_strokes.isEmpty) return;
    // 패드 영역 밖으로 나가면 살짝 클램프
    final clamped = Offset(
      p.dx.clamp(0, _padSize.width),
      p.dy.clamp(0, _padSize.height),
    );
    setState(() => _strokes.last.add(clamped));
  }

  Future<void> _confirm() async {
    if (_isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      // 고정 해상도(600x300)로 스케일해 내보내기 — 기기 크기와 무관하게 일정
      const exportW = 600.0;
      const exportH = 300.0;
      final sx = exportW / _padSize.width;
      final sy = exportH / _padSize.height;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, exportW, exportH),
        Paint()..color = Colors.white,
      );
      final paint = Paint()
        ..color = const Color(0xFF1F2937)
        ..strokeWidth = 3.0 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (final stroke in _strokes) {
        if (stroke.length < 2) continue;
        final path = Path()
          ..moveTo(stroke.first.dx * sx, stroke.first.dy * sy);
        for (final p in stroke.skip(1)) {
          path.lineTo(p.dx * sx, p.dy * sy);
        }
        canvas.drawPath(path, paint);
      }
      final picture = recorder.endRecording();
      final img = await picture.toImage(exportW.toInt(), exportH.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bytes == null) throw StateError('서명 이미지를 만들지 못했어요.');
      final b64 = base64Encode(bytes.buffer.asUint8List());
      if (!mounted) return;
      Navigator.of(context).pop(b64);
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서명 저장에 실패했어요. 다시 시도해주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('아래 칸에 손가락으로 서명해주세요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            // ── 서명 영역 ──
            AspectRatio(
              aspectRatio: 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _padSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.borderLight),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _start(d.localPosition),
                        onPanUpdate: (d) => _move(d.localPosition),
                        child: CustomPaint(
                          painter: _SignaturePainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _exporting
                    ? null
                    : () => setState(() => _strokes.clear()),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('다시 쓰기',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _exporting ? null : () => Navigator.of(context).pop(null),
          child: Text('취소',
              style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: (_isEmpty || _exporting) ? null : _confirm,
          child: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('서명 완료',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      color: AppColors.studentGreen)),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
