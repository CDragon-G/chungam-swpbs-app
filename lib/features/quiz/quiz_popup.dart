import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';

/// 🌟 깜짝 퀴즈 — 홈 진입 시 랜덤 팝업.
/// 하루 1회(서버 강제), 정답 시 학생 +5P / 교사 +3P.
///
/// 문제는 서버(todays_quiz)가 고른다. 두 종류가 섞여 나온다.
///   · 규칙 초성 퀴즈 — 우리 학교 규칙에서 한 낱말을 가린다
///   · 지식 퀴즈      — 관리자가 등록한 문제 ("수업규칙을 이르는 말은?" → 3끝)
///
/// 채점도 서버가 한다. 완전 일치가 아니라 어간까지 비교해서
/// '않았어요'와 '않아요'를 모두 정답으로 인정한다.
Future<void> maybeShowQuizPopup(
  BuildContext context,
  WidgetRef ref, {
  required bool isTeacher,
  double chance = 0.3,
}) async {
  if (Random().nextDouble() > chance) return;
  try {
    final attempted =
        await SupabaseService.client.rpc('quiz_attempted_today') as bool? ?? true;
    if (attempted) return;

    final res = await SupabaseService.client.rpc('todays_quiz');
    final q = Map<String, dynamic>.from(res as Map);
    if (q['ok'] != true) return;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _QuizDialog(quiz: q, isTeacher: isTeacher),
    );
  } catch (_) {
    // 퀴즈는 부가 기능 — 조용히 무시
  }
}

class _QuizDialog extends ConsumerStatefulWidget {
  const _QuizDialog({required this.quiz, required this.isTeacher});
  final Map<String, dynamic> quiz;
  final bool isTeacher;

  @override
  ConsumerState<_QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends ConsumerState<_QuizDialog> {
  final _answer = TextEditingController();
  bool _submitting = false;
  Map<String, dynamic>? _result;

  String get _question => widget.quiz['question'] as String? ?? '';
  String get _id => widget.quiz['id'] as String;

  /// 정답 후보들의 글자 수 (예: [3, 4]) — 중복정답을 알려주기 위한 값.
  List<int> get _lengths => ((widget.quiz['lengths'] as List?) ?? const [])
      .map((e) => (e as num).toInt())
      .where((n) => n > 0)
      .toList();

  /// 힌트 — 규칙 퀴즈는 가린 낱말의 초성, 지식 퀴즈는 등록된 힌트.
  String get _hint => (widget.quiz['hint'] as String?) ?? '';

  /// 'ㅇㅇㅇ, ㅇㅇㅇㅇ' — 몇 글자로 써도 되는지 눈으로 보여준다.
  String get _shapeHint {
    if (_lengths.isEmpty) return '';
    return _lengths.map((n) => 'ㅇ' * n).join(', ');
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_answer.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService.client.rpc('submit_quiz',
          params: {'p_rule_id': _id, 'p_answer': _answer.text.trim()});
      setState(() => _result = Map<String, dynamic>.from(res as Map));
    } catch (_) {
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final correct = r?['correct'] == true;

    return AlertDialog(
      title: Row(
        children: [
          const Text('🌟', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r == null ? '오늘의 깜짝 퀴즈' : (correct ? '정답이에요!' : '아쉬워요'),
              style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900, fontSize: 17),
            ),
          ),
        ],
      ),
      content: r == null ? _buildQuestion() : _buildResult(r, correct),
      actions: r == null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('다음에',
                    style: GoogleFonts.notoSansKr(
                        color: AppColors.textTertiary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.studentGreen),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('제출',
                        style:
                            GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ]
          : [
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.studentGreen),
                onPressed: () => Navigator.pop(context),
                child: Text('확인',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ],
    );
  }

  Widget _buildQuestion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.studentGreenLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _question,
            style: GoogleFonts.notoSansKr(
                fontSize: 14, height: 1.6, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        if (_hint.isNotEmpty)
          Text('힌트  $_hint',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.studentGreen)),
        if (_shapeHint.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '$_shapeHint  — 이렇게 써도 정답이에요',
            style: GoogleFonts.notoSansKr(
                fontSize: 11.5, color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _answer,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: '정답을 적어주세요',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '뜻이 통하면 정답으로 인정돼요.',
          style: GoogleFonts.notoSansKr(
              fontSize: 11.5, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildResult(Map<String, dynamic> r, bool correct) {
    final points = (r['points'] as num?)?.toInt() ?? 0;
    final keyword = r['keyword'] as String? ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(correct ? '🎉' : '🌱',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        if (keyword.isNotEmpty)
          Text('정답:  $keyword',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          correct
              ? '+${points}P 받았어요!'
              : '내일 또 도전할 수 있어요.',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
              fontSize: 13.5,
              height: 1.6,
              color: correct ? AppColors.studentGreen : AppColors.textSecondary,
              fontWeight: correct ? FontWeight.w800 : FontWeight.w600),
        ),
      ],
    );
  }
}
