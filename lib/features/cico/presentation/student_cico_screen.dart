import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/signature_pad.dart';
import '../models/cico.dart';
import '../providers/cico_provider.dart';

/// 학생: 내 CICO — 오늘 카드 확인, 소감 작성, 보호자 서명.
class StudentCicoScreen extends ConsumerStatefulWidget {
  const StudentCicoScreen({super.key});

  @override
  ConsumerState<StudentCicoScreen> createState() => _State();
}

class _State extends ConsumerState<StudentCicoScreen> {
  bool _loading = true;
  String? _error;
  CicoEnrollment? _enrollment;
  CicoDaily? _today;
  List<CicoScore> _scores = [];
  final _reflectionCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reflectionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(cicoRepositoryProvider);
      final e = await repo.myActiveEnrollment();
      CicoDaily? today;
      List<CicoScore> scores = [];
      if (e != null) {
        today = await repo.fetchDaily(e.id, KstDate.today());
        if (today != null) {
          scores = await repo.fetchScores(today.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _enrollment = e;
        _today = today;
        _scores = scores;
        _reflectionCtrl.text = today?.studentReflection ?? '';
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

  Future<void> _saveReflection() async {
    final daily = _today;
    if (daily == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(cicoRepositoryProvider).studentNote(
            dailyId: daily.id,
            reflection: _reflectionCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('소감을 저장했어요! ✍️'),
          backgroundColor: AppColors.studentGreen));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sign() async {
    final daily = _today;
    if (daily == null) return;
    final b64 = await SignaturePadDialog.show(context);
    if (b64 == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(cicoRepositoryProvider).studentNote(
            dailyId: daily.id,
            signatureBase64: b64,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('보호자 확인이 완료되었어요! 👨‍👩‍👧'),
          backgroundColor: AppColors.studentGreen));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('나의 동행 점검',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _enrollment == null
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _body(_enrollment!),
                    ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌱', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('진행 중인 동행 점검이 없어요.',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _body(CicoEnrollment e) {
    final history = ref.watch(cicoHistoryProvider(e.id));
    final days = KstDate.today().difference(e.startDate).inDays + 1;
    final today = _today;

    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        // ── 헤더 카드 ──
        PbsCard(
          color: AppColors.teacherNavy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🤝 멘토 선생님과 함께하는 $days일차',
                  style: GoogleFonts.notoSansKr(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('목표 달성률 ${e.goalPct}%',
                  style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('매일 목표를 채우면 곧 졸업이에요! 🎓',
                  style: GoogleFonts.notoSansKr(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),

        // ── 최근 달성률 ──
        history.maybeWhen(
          data: (h) => h.isEmpty ? const SizedBox.shrink() : _strip(h, e),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSizes.md),

        // ── 오늘 카드 ──
        Text(DateFormat('M월 d일 (E)', 'ko_KR').format(KstDate.today()),
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 8),

        if (today == null)
          PbsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '아직 오늘 점검이 저장되지 않았어요.\n멘토 선생님과 체크인·체크아웃을 해보세요! ☀️',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.6),
              ),
            ),
          )
        else ...[
          // 달성률
          PbsCard(
            color: today.pct >= e.goalPct
                ? AppColors.studentGreenLight
                : AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  today.pct >= e.goalPct ? '🎉' : '💪',
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 10),
                Text('오늘 ${today.pct.toStringAsFixed(0)}%',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: today.pct >= e.goalPct
                            ? AppColors.success
                            : AppColors.textPrimary)),
                const SizedBox(width: 8),
                Text('/ 목표 ${e.goalPct}%',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.sm),

          if (today.checkinNote != null && today.checkinNote!.isNotEmpty)
            _noteCard('☀️ 오늘의 목표', today.checkinNote!),
          if (_scores.isNotEmpty) _scoresCard(),
          if (today.checkoutNote != null && today.checkoutNote!.isNotEmpty)
            _noteCard('🌙 멘토 선생님의 한마디', today.checkoutNote!),

          const SizedBox(height: AppSizes.md),

          // ── 소감 ──
          Text('✍️ 오늘의 소감',
              style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _reflectionCtrl,
            maxLines: 3,
            maxLength: 200,
            enabled: !_saving,
            style: GoogleFonts.notoSansKr(fontSize: 13),
            decoration: InputDecoration(
              hintText: '오늘 하루는 어땠나요?',
              hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  borderSide: BorderSide.none),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: _saving ? null : _saveReflection,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teacherNavy,
                side: const BorderSide(color: AppColors.teacherNavy),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
              ),
              child: Text('소감 저장',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // ── 보호자 확인 ──
          if (today.hasParentSign)
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.studentGreenLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Row(
                children: [
                  const Text('✅', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text('보호자 확인 완료',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800,
                          color: AppColors.success)),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _sign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.studentGreen,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.draw_rounded, size: 20),
                label: Text('보호자 서명 받기',
                    style:
                        GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _strip(List<CicoDaily> h, CicoEnrollment e) {
    final recent = h.length <= 7 ? h : h.sublist(h.length - 7);
    return PbsCard(
      child: Row(
        children: recent.map((d) {
          final ok = d.pct >= e.goalPct;
          return Expanded(
            child: Column(
              children: [
                Text(ok ? '🌟' : '·',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  decoration: BoxDecoration(
                    color:
                        ok ? AppColors.studentGreen : AppColors.borderLight,
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
    );
  }

  Widget _noteCard(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.sm),
        child: PbsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teacherNavy)),
              const SizedBox(height: 4),
              Text(body,
                  style:
                      GoogleFonts.notoSansKr(fontSize: 13, height: 1.5)),
            ],
          ),
        ),
      );

  Widget _scoresCard() {
    final groups = <String, List<CicoScore>>{};
    for (final s in _scores) {
      groups.putIfAbsent(s.space ?? '기타', () => []).add(s);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groups.entries
              .expand((g) => [
                    Text(g.key,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.teacherNavy)),
                    const SizedBox(height: 4),
                    ...g.value.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(s.itemLabel,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 12, height: 1.4)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: s.score == 2
                                      ? AppColors.studentGreen
                                      : s.score == 1
                                          ? AppColors.warning
                                          : AppColors.borderLight,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text('${s.score}',
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: s.score == 0
                                            ? AppColors.textSecondary
                                            : Colors.white)),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 6),
                  ])
              .toList(),
        ),
      ),
    );
  }
}
