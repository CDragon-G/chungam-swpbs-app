import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../school/providers/school_provider.dart';
import '../models/cico.dart';
import '../providers/cico_provider.dart';

/// 교사(멘토): 하루치 CICO 카드 — 체크인 · 규칙별 0/1/2 · 체크아웃.
class CicoDailyScreen extends ConsumerStatefulWidget {
  const CicoDailyScreen({super.key, required this.enrollment});
  final CicoEnrollment enrollment;

  @override
  ConsumerState<CicoDailyScreen> createState() => _State();
}

class _State extends ConsumerState<CicoDailyScreen> {
  DateTime _date = KstDate.today();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  CicoDaily? _existing;
  List<CicoScoreInput> _inputs = [];
  final _checkinCtrl = TextEditingController();
  final _checkoutCtrl = TextEditingController();

  CicoEnrollment get _e => widget.enrollment;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  @override
  void dispose() {
    _checkinCtrl.dispose();
    _checkoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDay() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(cicoRepositoryProvider);
      final rules = await ref.read(schoolRulesProvider.future);
      final daily = await repo.fetchDaily(_e.id, _date);

      // 기존 점수 맵 (rule_id 우선, 문구 보조)
      final byRule = <String, int>{};
      final byLabel = <String, int>{};
      if (daily != null) {
        final scores = await repo.fetchScores(daily.id);
        for (final s in scores) {
          if (s.ruleId != null) byRule[s.ruleId!] = s.score;
          byLabel[s.itemLabel] = s.score;
        }
      }

      // 그 학교의 현재 규칙으로 항목 구성 (학교마다 다름)
      final inputs = rules
          .map((r) => CicoScoreInput(
                ruleId: r.id,
                itemLabel: r.ruleText,
                category: r.category,
                space: r.space,
                score: byRule[r.id] ?? byLabel[r.ruleText] ?? 0,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _existing = daily;
        _inputs = inputs;
        _checkinCtrl.text = daily?.checkinNote ?? '';
        _checkoutCtrl.text = daily?.checkoutNote ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = translateError(e);
        _loading = false;
      });
    }
  }

  void _changeDate(int deltaDays) {
    final next = _date.add(Duration(days: deltaDays));
    if (next.isAfter(KstDate.today())) return; // 미래 금지
    if (next.isBefore(_e.startDate)) return; // 시작일 이전 금지
    setState(() => _date = next);
    _loadDay();
  }

  double get _livePct {
    if (_inputs.isEmpty) return 0;
    final total = _inputs.fold<int>(0, (a, b) => a + b.score);
    return (total / (_inputs.length * 2)) * 100;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final pct = await ref.read(cicoRepositoryProvider).saveDay(
            enrollmentId: _e.id,
            date: _date,
            checkin: _checkinCtrl.text.trim(),
            checkout: _checkoutCtrl.text.trim(),
            scores: _inputs,
          );
      ref.invalidate(cicoHistoryProvider(_e.id));
      if (!mounted) return;
      final achieved = pct >= _e.goalPct;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(achieved
            ? '저장 완료! 오늘 ${pct.toStringAsFixed(0)}% — 목표 달성 🎉'
            : '저장 완료! 오늘 ${pct.toStringAsFixed(0)}% (목표 ${_e.goalPct}%)'),
        backgroundColor:
            achieved ? AppColors.studentGreen : AppColors.teacherNavy,
      ));
      await _loadDay(); // daily id 갱신 (소감·서명 표시용)
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(String status) async {
    final label = status == 'graduated' ? '졸업' : '중단';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('CICO $label',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          status == 'graduated'
              ? '${_e.studentName ?? '학생'} 학생을 졸업 처리할까요?\n'
                  '목표를 꾸준히 달성했다면 축하할 일이에요! 🎓'
              : 'CICO를 중단할까요? 필요하면 나중에 다시 시작할 수 있어요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(label,
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      color: status == 'graduated'
                          ? AppColors.studentGreen
                          : const Color(0xFFDC2626)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(cicoRepositoryProvider).setStatus(_e.id, status);
      ref.invalidate(cicoEnrollmentsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'graduated'
            ? '🎓 졸업 처리했어요. 축하해요!'
            : 'CICO를 중단했어요.'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = KstDate.isSameDay(_date, KstDate.today());
    final history = ref.watch(cicoHistoryProvider(_e.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '${_e.studentName ?? '학생'} CICO',
          style: GoogleFonts.notoSansKr(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary),
            onSelected: _setStatus,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'graduated',
                  child: Text('🎓 졸업 처리',
                      style: GoogleFonts.notoSansKr(fontSize: 13))),
              PopupMenuItem(
                  value: 'stopped',
                  child: Text('중단',
                      style: GoogleFonts.notoSansKr(fontSize: 13))),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(_error!,
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textSecondary)),
                ))
              : ListView(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  children: [
                    // ── 날짜 이동 ──
                    Row(
                      children: [
                        IconButton(
                            onPressed: () => _changeDate(-1),
                            icon: const Icon(Icons.chevron_left_rounded)),
                        Expanded(
                          child: Text(
                            DateFormat('M월 d일 (E)', 'ko_KR').format(_date) +
                                (isToday ? ' · 오늘' : ''),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                        IconButton(
                            onPressed:
                                isToday ? null : () => _changeDate(1),
                            icon: const Icon(Icons.chevron_right_rounded)),
                      ],
                    ),

                    // ── 최근 추이 ──
                    history.maybeWhen(
                      data: (h) => h.isEmpty
                          ? const SizedBox.shrink()
                          : _historyStrip(h),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // ── 아침 체크인 ──
                    _sectionTitle('☀️ 아침 체크인 — 오늘의 목표'),
                    TextField(
                      controller: _checkinCtrl,
                      maxLines: 2,
                      enabled: !_saving,
                      style: GoogleFonts.notoSansKr(fontSize: 13),
                      decoration: _inputDeco('예: 오늘은 수업 시간에 3번 손 들고 발표하기!'),
                    ),
                    const SizedBox(height: AppSizes.lg),

                    // ── 규칙별 점수 ──
                    _sectionTitle('📋 오늘의 행동 점검 (0 · 1 · 2)'),
                    Text('0 = 도움이 필요해요 · 1 = 보통 · 2 = 잘했어요',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 11, color: AppColors.textTertiary)),
                    const SizedBox(height: 8),
                    ..._groupedScoreCards(),
                    const SizedBox(height: AppSizes.lg),

                    // ── 하교 체크아웃 ──
                    _sectionTitle('🌙 하교 체크아웃 — 멘토 피드백'),
                    TextField(
                      controller: _checkoutCtrl,
                      maxLines: 2,
                      enabled: !_saving,
                      style: GoogleFonts.notoSansKr(fontSize: 13),
                      decoration: _inputDeco('예: 발표 2번 성공! 내일은 3번 도전해보자 💪'),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // ── 학생 소감·보호자 확인 (읽기) ──
                    if (_existing?.studentReflection != null &&
                        _existing!.studentReflection!.isNotEmpty)
                      _readonlyBox('✍️ 학생 소감', _existing!.studentReflection!),
                    if (_existing?.hasParentSign == true)
                      _readonlyBox('👨‍👩‍👧 보호자 확인',
                          '서명 완료 (${DateFormat('M/d HH:mm').format(_existing!.parentSignedAt!.toLocal())})'),

                    const SizedBox(height: AppSizes.md),

                    // ── 저장 ──
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _livePct >= _e.goalPct
                              ? AppColors.studentGreen
                              : AppColors.teacherNavy,
                          foregroundColor: Colors.white,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text(
                                '저장 — 현재 ${_livePct.toStringAsFixed(0)}% (목표 ${_e.goalPct}%)',
                                style: GoogleFonts.notoSansKr(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
    );
  }

  // ── 위젯 빌더들 ───────────────────────────────────────────

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w800, fontSize: 14)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.notoSansKr(
            fontSize: 12, color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: BorderSide.none),
      );

  Widget _historyStrip(List<CicoDaily> h) {
    final recent = h.length <= 7 ? h : h.sublist(h.length - 7);
    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('최근 달성률',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: recent.map((d) {
              final ok = d.pct >= _e.goalPct;
              return Expanded(
                child: Column(
                  children: [
                    Text('${d.pct.round()}',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: ok
                                ? AppColors.studentGreen
                                : AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      decoration: BoxDecoration(
                        color: ok
                            ? AppColors.studentGreen
                            : AppColors.borderLight,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(DateFormat('M/d').format(d.entryDate),
                        style: GoogleFonts.notoSansKr(
                            fontSize: 9, color: AppColors.textTertiary)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedScoreCards() {
    // 장소(space)별 그룹 — 학교가 설정한 규칙 구조 그대로
    final groups = <String, List<CicoScoreInput>>{};
    for (final i in _inputs) {
      groups.putIfAbsent(i.space ?? '기타', () => []).add(i);
    }
    return groups.entries
        .map((g) => Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: PbsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.key,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.teacherNavy)),
                    const SizedBox(height: 6),
                    ...g.value.map(_scoreRow),
                  ],
                ),
              ),
            ))
        .toList();
  }

  Widget _scoreRow(CicoScoreInput input) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(input.itemLabel,
                style: GoogleFonts.notoSansKr(fontSize: 12.5, height: 1.4)),
          ),
          const SizedBox(width: 8),
          Row(
            children: [0, 1, 2].map((v) {
              final sel = input.score == v;
              return GestureDetector(
                onTap: _saving
                    ? null
                    : () => setState(() => input.score = v),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(left: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? (v == 2
                            ? AppColors.studentGreen
                            : v == 1
                                ? AppColors.warning
                                : AppColors.textTertiary)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: sel
                            ? Colors.transparent
                            : AppColors.borderLight),
                  ),
                  child: Text('$v',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: sel ? Colors.white : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _readonlyBox(String title, String body) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSizes.sm),
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.studentGreenLight,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success)),
            const SizedBox(height: 4),
            Text(body,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5, height: 1.5)),
          ],
        ),
      );
}
