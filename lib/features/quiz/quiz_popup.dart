import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/chosung.dart';

/// 🌟 규칙 초성 깜짝 퀴즈 — 홈 진입 시 랜덤 팝업.
/// 하루 1회(서버 강제), 정답 시 학생 +5P / 교사 +3P.
/// 정답 검증은 서버(submit_quiz RPC)가 동일한 결정적 키워드로 수행한다.
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

    final rows = await SupabaseService.client
        .from('school_rules')
        .select('id, space, rule_text')
        .eq('is_active', true);
    final rules = (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => quizKeyword(r['rule_text'] as String) != null)
        .toList();
    if (rules.isEmpty) return;
    final rule = rules[Random().nextInt(rules.length)];

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _QuizDialog(rule: rule, isTeacher: isTeacher),
    );
  } catch (_) {
    // 퀴즈는 부가 기능 — 조용히 무시
  }
}

class _QuizDialog extends ConsumerStatefulWidget {
  const _QuizDialog({required this.rule, required this.isTeacher});
  final Map<String, dynamic> rule;
  final bool isTeacher;

  @override
  ConsumerState<_QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends ConsumerState<_QuizDialog> {
  final _answer = TextEditingController();
  bool _submitting = false;
  Map<String, dynamic>? _result;

  String get _ruleText => widget.rule['rule_text'] as String;
  String get _keyword => quizKeyword(_ruleText)!;

  /// 키워드를 초성으로 가린 문장: "수업 시작 종이..." → "ㅅㅇ 시작 종이..."
  String get _maskedText =>
      _ruleText.replaceFirst(_keyword, '［${toChosung(_keyword)}］');

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_answer.text.trim().isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService.client.rpc('submit_quiz', params: {
        'p_rule_id': widget.rule['id'],
        'p_answer': _answer.text.trim(),
      });
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
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        r == null
            ? '⚡ 깜짝 초성 퀴즈!'
            : (r['correct'] == true ? '🎉 정답이에요!' : '아쉬워요!'),
        style: GoogleFonts.notoSansKr(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r == null) ...[
            Text(
              '우리 학교 「${widget.rule['space']}」 규칙이에요.\n［ ］ 속 초성에 들어갈 말은?',
              style: GoogleFonts.notoSansKr(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _maskedText,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15, fontWeight: FontWeight.w800, height: 1.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '정답 입력',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ] else ...[
            Text(
              r['correct'] == true
                  ? '「$_keyword」 맞아요!\n+${r['points']}P 를 받았어요 🌱'
                  : '정답은 「${r['keyword']}」였어요.\n내일 또 도전해요!',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                  fontSize: 15, fontWeight: FontWeight.w800, height: 1.6),
            ),
          ],
        ],
      ),
      actions: r == null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('다음에',
                    style:
                        GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
              ),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: Text(_submitting ? '확인 중...' : '제출!',
                    style:
                        GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ]
          : [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: Text('닫기',
                    style:
                        GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ],
    );
  }
}
