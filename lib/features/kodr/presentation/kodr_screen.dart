import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/student_picker_sheet.dart';
import '../../cico/presentation/cico_start_dialog.dart';
import '../../growth/growth_celebration.dart';
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

  void _showLegalInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(AppSizes.xl),
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: AppColors.teacherNavy, size: 26),
                const SizedBox(width: 8),
                Text('개인정보 안내 · 법적 근거',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            _legalSection(
              '🎯  목적은 지원, 처벌이 아닙니다',
              'K-ODR은 학생의 어려움을 조기에 발견해 교육적으로 지원하기 위한 '
                  '관찰 기록입니다. 징계·낙인·처벌을 위한 자료가 아니며, 학생을 '
                  '더 잘 돕기 위한 긍정적 행동지원(PBS)의 도구입니다.',
            ),
            _legalSection(
              '⚖️  법적 근거',
              '• 초·중등교육법 제20조의2 (교원의 학생생활지도)\n'
                  '• 교원의 학생생활지도에 관한 고시 (교육부고시 제2023-28호)\n'
                  '• 개인정보 보호법 제15조 — 법령에서 정한 소관 업무 및 '
                  '교육 목적 수행을 위한 개인정보의 적법한 처리\n'
                  '• 학교생활기록 작성 및 관리지침\n\n'
                  '학교와 교원은 학생 생활지도를 위해 행동을 관찰·기록할 '
                  '법적 권한과 책무를 가집니다.',
            ),
            _legalSection(
              '🔒  엄격한 접근 제한',
              '• 같은 학교의 교사만 열람할 수 있습니다.\n'
                  '• 학생 본인, 다른 학생, 외부에는 공개되지 않습니다.\n'
                  '• 명예의 전당 등 공개 화면에서는 이름이 마스킹(신*용)됩니다.\n'
                  '• 데이터는 암호화 전송·저장되며 교육 목적 외 사용이 금지됩니다.',
            ),
            _legalSection(
              '🤝  지원으로 이어집니다',
              '반복되는 어려움이 확인되면(월 3건 이상) 멘토 교사와 함께하는 '
                  '동행 지원(CICO)을 제안합니다. 기록은 비난이 아니라 '
                  '맞춤형 도움의 출발점입니다.',
            ),
            const SizedBox(height: AppSizes.md),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teacherNavy,
                    foregroundColor: Colors.white),
                child: Text('확인했습니다',
                    style:
                        GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: AppSizes.md),
          ],
        ),
      ),
    );
  }

  Widget _legalSection(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.teacherNavy)),
            const SizedBox(height: 6),
            Text(body,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    height: 1.7,
                    color: AppColors.textSecondary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('K-ODR 행동 지원',
                style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('행동 기록 · 지원이 필요한 학생 발견',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined,
                color: AppColors.teacherNavy),
            tooltip: '법적 근거 · 개인정보 안내',
            onPressed: () => _showLegalInfo(context),
          ),
        ],
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
                ...cico.map((e) => _row(context, ref, e, highlight: true)),
                const SizedBox(height: AppSizes.lg),
              ],
              if (others.isNotEmpty) ...[
                Text('이달 기록된 학생',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 10),
                ...others.map((e) => _row(context, ref, e)),
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

  Widget _row(BuildContext context, WidgetRef ref, KodrSummaryEntry e,
          {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.sm),
        child: PbsCard(
          color: highlight ? const Color(0xFFFFF7ED) : null,
          border: highlight
              ? Border.all(color: AppColors.warning.withValues(alpha: 0.4))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${e.nickname} (${e.classLabel})',
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  if (highlight)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
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
              if (highlight)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => showCicoStartDialog(
                      context,
                      ref,
                      studentUserId: e.studentId,
                      studentName: e.nickname,
                      initialReason:
                          '이달 K-ODR ${e.recordCount}건 — 동행 지원 시작',
                    ),
                    icon: const Text('🤝', style: TextStyle(fontSize: 14)),
                    label: Text('CICO 시작하기',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.teacherNavy)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
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
    final picked = await StudentPickerSheet.show(context, students,
        title: '학생 선택');
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
      celebrateGrowth(context, ref,
          headline: '행동 기록 완료 — 학생 지원에 활용돼요 📋');
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
