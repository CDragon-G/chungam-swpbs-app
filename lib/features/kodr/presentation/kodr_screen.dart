import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../school/providers/school_provider.dart';
import '../constants/kodr_codes.dart';
import '../models/kodr.dart';
import '../providers/kodr_provider.dart';

/// K-ODR — 행동 기록 + 월별 현황. 처벌이 아닌 학생 지원을 위한 도구.
class KodrScreen extends ConsumerStatefulWidget {
  const KodrScreen({super.key});

  @override
  ConsumerState<KodrScreen> createState() => _State();
}

class _State extends ConsumerState<KodrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('K-ODR 행동 지원',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.teacherNavy,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.teacherNavy,
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
          tabs: const [Tab(text: '이달 현황'), Tab(text: '기록하기')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_SummaryTab(), _RecordTab()],
      ),
    );
  }
}

// ── 처벌 아닌 지원 안내 배너 ──────────────────────────────────
class _SupportBanner extends StatelessWidget {
  const _SupportBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.studentGreenLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          const Text('💚', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'K-ODR은 처벌이 아니라, 학생을 더 잘 돕기 위한 관심의 기록입니다. '
              '반복되는 어려움을 빨리 발견해 함께 지원하는 데 목적이 있어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 이달 현황 탭 ──────────────────────────────────────────────
class _SummaryTab extends ConsumerWidget {
  const _SummaryTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kodrSummaryProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(kodrSummaryProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(translateError(e))))]),
        data: (list) {
          final cico = list.where((e) => e.needsCico).toList();
          final others = list.where((e) => !e.needsCico).toList();
          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              const _SupportBanner(),
              const SizedBox(height: AppSizes.md),
              if (cico.isNotEmpty) ...[
                Text('🤝 함께 지원이 필요한 학생 (이달 3건 이상)',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 4),
                Text('멘토 선생님과 함께하는 동행(CICO)을 시작해보세요.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                ...cico.map((e) => _row(e, highlight: true)),
                const SizedBox(height: AppSizes.lg),
              ],
              if (others.isNotEmpty) ...[
                Text('이달 기록된 학생',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 10),
                ...others.map((e) => _row(e)),
              ],
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('이달 기록이 없어요.',
                        style: GoogleFonts.notoSansKr(
                            color: AppColors.textTertiary)),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _row(KodrSummaryEntry e, {bool highlight = false}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.sm),
        child: PbsCard(
          color: highlight ? const Color(0xFFFFF7ED) : null,
          border: highlight
              ? Border.all(color: AppColors.warning.withValues(alpha: 0.4))
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text('${e.nickname} (${e.classLabel})',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (highlight)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('지원 권장',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309))),
                ),
              Text('${e.recordCount}건',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w900,
                      color: AppColors.teacherNavy)),
            ],
          ),
        ),
      );
}

// ── 기록하기 탭 ──────────────────────────────────────────────
class _RecordTab extends ConsumerStatefulWidget {
  const _RecordTab();
  @override
  ConsumerState<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends ConsumerState<_RecordTab> {
  Map<String, dynamic>? _student; // 선택된 학생
  DateTime _date = KstDate.today();
  String? _behavior, _place, _situation, _immediate, _secondary, _reaction, _role;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickStudent() async {
    final students = ref.read(schoolStudentsProvider).value ?? [];
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            Text('학생 선택',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 12),
            ...students.map((s) => ListTile(
                  title: Text(
                      '${s['nickname']} (${s['grade']}-${s['class_num']}-${s['student_num']})',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, s),
                )),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _student = picked);
  }

  Future<void> _save() async {
    final profile = ref.read(profileProvider).value;
    if (_student == null) {
      _toast('학생을 선택해주세요.');
      return;
    }
    if (_behavior == null) {
      _toast('행동양상을 선택해주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(kodrRepositoryProvider).create(
            schoolId: profile!.schoolId!,
            studentId: _student!['user_id'] as String,
            occurredDate: _date,
            behavior: _behavior!,
            place: _place,
            situation: _situation,
            immediateResponse: _immediate,
            secondaryResponse: _secondary,
            studentReaction: _reaction,
            authorRole: _role,
            note: _note.text.trim(),
          );
      ref.invalidate(kodrSummaryProvider);
      if (!mounted) return;
      _toast('기록되었습니다. 학생 지원에 활용됩니다.');
      setState(() {
        _behavior = _place = _situation = _immediate =
            _secondary = _reaction = null;
        _note.clear();
      });
    } catch (e) {
      _toast(translateError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        const _SupportBanner(),
        const SizedBox(height: AppSizes.md),
        // 학생 선택
        PbsCard(
          onTap: _pickStudent,
          child: Row(
            children: [
              const Icon(Icons.person_search_rounded,
                  color: AppColors.teacherNavy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _student == null
                      ? '학생 선택'
                      : '${_student!['nickname']} (${_student!['grade']}-${_student!['class_num']}-${_student!['student_num']})',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w700,
                      color: _student == null
                          ? AppColors.textTertiary
                          : AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        // 날짜
        _dateField(),
        const SizedBox(height: AppSizes.md),
        _dropdown('행동양상 *', KodrCodes.behaviors, _behavior,
            (v) => setState(() => _behavior = v)),
        _dropdown('장소', KodrCodes.places, _place,
            (v) => setState(() => _place = v)),
        _dropdown('상황', KodrCodes.situations, _situation,
            (v) => setState(() => _situation = v)),
        _dropdown('즉각적 대응', KodrCodes.responses, _immediate,
            (v) => setState(() => _immediate = v)),
        _dropdown('2차적 대응', KodrCodes.responses, _secondary,
            (v) => setState(() => _secondary = v)),
        _dropdown('학생 반응', KodrCodes.studentReactions, _reaction,
            (v) => setState(() => _reaction = v)),
        _dropdown('작성자', KodrCodes.authorRoles, _role,
            (v) => setState(() => _role = v)),
        const SizedBox(height: 6),
        TextField(
          controller: _note,
          maxLines: 3,
          style: GoogleFonts.notoSansKr(fontSize: 14),
          decoration: InputDecoration(
            labelText: '메모 (선택)',
            labelStyle: GoogleFonts.notoSansKr(fontSize: 13),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherNavy,
                foregroundColor: Colors.white),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('기록 저장',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _dateField() => PbsCard(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2025),
            lastDate: DateTime.now(),
          );
          if (d != null) setState(() => _date = d);
        },
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: AppColors.teacherNavy),
            const SizedBox(width: 10),
            Text(KstDate.formatYmd(_date),
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _dropdown(String label, List<String> items, String? value,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                hint: Text('선택',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14, color: AppColors.textTertiary)),
                items: items
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: GoogleFonts.notoSansKr(fontSize: 14),
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
