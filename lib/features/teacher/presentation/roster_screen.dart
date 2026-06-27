import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../school/models/roster_entry.dart';
import '../../school/providers/school_provider.dart';

/// 관리자 교사용 학생 명단 관리 화면.
/// 엑셀에서 복사한 명단을 붙여넣어 일괄 등록하고, 학급별 PIN을 조회한다.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _State();
}

class _State extends ConsumerState<RosterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

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
        title: Text(
          '학생 명단 관리',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.teacherNavy,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.teacherNavy,
          isScrollable: true,
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: '직접 추가'),
            Tab(text: '일괄 업로드'),
            Tab(text: 'PIN 조회'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _AddOneTab(),
          _UploadTab(),
          _PinListTab(),
        ],
      ),
    );
  }
}

// ── 직접 추가 탭 ──────────────────────────────────────────────

class _AddOneTab extends ConsumerStatefulWidget {
  const _AddOneTab();
  @override
  ConsumerState<_AddOneTab> createState() => _AddOneTabState();
}

class _AddOneTabState extends ConsumerState<_AddOneTab> {
  final _grade = TextEditingController();
  final _classNum = TextEditingController();
  final _studentNum = TextEditingController();
  final _name = TextEditingController();
  final _numFocus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _grade.dispose();
    _classNum.dispose();
    _studentNum.dispose();
    _name.dispose();
    _numFocus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final profile = ref.read(profileProvider).value;
    final g = int.tryParse(_grade.text);
    final c = int.tryParse(_classNum.text);
    final n = int.tryParse(_studentNum.text);
    final name = _name.text.trim();
    if (profile?.schoolId == null) return;
    if (g == null || c == null || n == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학년·반·번호·이름을 모두 입력해주세요.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(schoolRepositoryProvider).addRosterEntry(
            schoolId: profile!.schoolId!,
            grade: g,
            classNum: c,
            studentNum: n,
            name: name,
          );
      ref.invalidate(schoolRosterProvider);
      if (!mounted) return;
      // 번호만 +1, 학년/반/이름은 유지 → 연속 입력 편하게
      setState(() {
        _studentNum.text = '${n + 1}';
        _name.clear();
      });
      _numFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$g학년 $c반 $n번 $name 등록 완료'),
            duration: const Duration(milliseconds: 900)),
      );
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
    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        PbsCard(
          color: AppColors.teacherNavyLight,
          child: Text(
            '학생을 한 명씩 등록해요.\n'
            '등록하면 번호가 자동으로 +1 되니, 같은 반은 이름만 바꿔가며 빠르게 추가할 수 있어요.\n'
            '전교생을 한 번에 등록하려면 자람 웹사이트를 이용하세요.',
            style: GoogleFonts.notoSansKr(
                fontSize: 12, height: 1.6, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: [
            Expanded(
              child: PbsTextField(
                controller: _grade,
                label: '학년',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: PbsTextField(
                controller: _classNum,
                label: '반',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: PbsTextField(
                controller: _studentNum,
                focusNode: _numFocus,
                label: '번호',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        PbsTextField(
          controller: _name,
          label: '이름',
          hint: '예: 홍길동',
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: AppSizes.lg),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _add,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherNavy,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('등록하기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

// ── 업로드 탭 ──────────────────────────────────────────────────

class _UploadTab extends ConsumerStatefulWidget {
  const _UploadTab();
  @override
  ConsumerState<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends ConsumerState<_UploadTab> {
  final _controller = TextEditingController();
  List<RosterDraftRow> _parsed = [];
  List<String> _errors = [];
  bool _uploading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _preview() {
    final (rows, errors) = RosterParser.parse(_controller.text);
    setState(() {
      _parsed = rows;
      _errors = errors;
    });
  }

  Future<void> _upload() async {
    final profile = ref.read(profileProvider).value;
    if (profile?.schoolId == null || _parsed.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final n = await ref.read(schoolRepositoryProvider).uploadRoster(
            schoolId: profile!.schoolId!,
            rows: _parsed,
          );
      ref.invalidate(schoolRosterProvider);
      if (!mounted) return;
      setState(() {
        _controller.clear();
        _parsed = [];
        _errors = [];
      });
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('등록 완료',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Text(
            '$n명의 학생 명단을 등록했어요.\n'
            '"PIN 조회" 탭에서 학급별 PIN을 확인하고\n'
            '담임선생님을 통해 학생에게 전달하세요.',
            style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('확인',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        PbsCard(
          color: AppColors.teacherNavyLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📋 명단 등록 방법',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      color: AppColors.teacherNavy)),
              const SizedBox(height: 8),
              Text(
                '1. 엑셀에서 학년·반·번호·이름 4개 열을 선택해 복사하세요.\n'
                '2. 아래 칸에 붙여넣고 "미리보기"를 누르세요.\n'
                '3. 내용을 확인한 뒤 "명단 등록"을 누르세요.\n\n'
                '예시:\n'
                '1  1  1  홍길동\n'
                '1  1  2  김철수\n'
                '1  2  1  이영희',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, height: 1.7, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        TextField(
          controller: _controller,
          maxLines: 8,
          style: GoogleFonts.robotoMono(fontSize: 13),
          decoration: InputDecoration(
            hintText: '여기에 엑셀에서 복사한 명단을 붙여넣으세요',
            hintStyle: GoogleFonts.notoSansKr(
                fontSize: 13, color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _preview,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teacherNavy,
                  side: const BorderSide(color: AppColors.teacherNavy),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('미리보기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    (_parsed.isEmpty || _uploading) ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('명단 등록 (${_parsed.length}명)',
                        style:
                            GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        if (_errors.isNotEmpty) ...[
          const SizedBox(height: AppSizes.md),
          PbsCard(
            color: AppColors.danger.withValues(alpha: 0.06),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⚠️ 확인이 필요한 줄 (${_errors.length}개)',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                        fontSize: 13)),
                const SizedBox(height: 6),
                ..._errors.take(10).map((e) => Text('• $e',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.danger))),
              ],
            ),
          ),
        ],
        if (_parsed.isNotEmpty) ...[
          const SizedBox(height: AppSizes.md),
          Text('미리보기 (${_parsed.length}명)',
              style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 6),
          ..._parsed.take(50).map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${r.grade}학년 ${r.classNum}반 ${r.studentNum}번  ${r.name}',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              )),
          if (_parsed.length > 50)
            Text('... 외 ${_parsed.length - 50}명',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textTertiary)),
        ],
      ],
    );
  }
}

// ── PIN 조회 탭 ────────────────────────────────────────────────

class _PinListTab extends ConsumerWidget {
  const _PinListTab();

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider).value;
    if (profile?.schoolId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('전체 명단 삭제',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '등록된 모든 학생 명단을 삭제할까요?\n'
          '(이미 가입한 학생의 계정은 유지되고, 명단 정보만 삭제됩니다.)',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('전체 삭제',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref
          .read(schoolRepositoryProvider)
          .clearRoster(profile!.schoolId!);
      ref.invalidate(schoolRosterProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$n명의 명단을 삭제했어요.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(schoolRosterProvider);
    return rosterAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(translateError(e))),
      data: (roster) {
        if (roster.isEmpty) {
          return Center(
            child: Text('등록된 명단이 없어요.\n"직접 추가" 또는 "일괄 업로드"로 먼저 등록하세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
          );
        }
        final groups = <String, List<RosterEntry>>{};
        for (final r in roster) {
          groups.putIfAbsent('${r.grade}-${r.classNum}', () => []).add(r);
        }
        final keys = groups.keys.toList()
          ..sort((a, b) {
            final pa = a.split('-').map(int.parse).toList();
            final pb = b.split('-').map(int.parse).toList();
            return pa[0] != pb[0] ? pa[0] - pb[0] : pa[1] - pb[1];
          });

        return ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('전체 ${roster.length}명',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                TextButton.icon(
                  onPressed: () => _clearAll(context, ref),
                  icon: const Icon(Icons.delete_sweep_rounded,
                      size: 18, color: AppColors.danger),
                  label: Text('전체 삭제',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                          fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.sm),
            for (final k in keys) ...[
              _ClassPinCard(gradeClass: k, entries: groups[k]!),
              const SizedBox(height: AppSizes.md),
            ],
          ],
        );
      },
    );
  }
}

class _ClassPinCard extends ConsumerWidget {
  const _ClassPinCard({required this.gradeClass, required this.entries});
  final String gradeClass;
  final List<RosterEntry> entries;

  Future<void> _deleteOne(
      BuildContext context, WidgetRef ref, RosterEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('명단 삭제',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text('${e.name} 학생을 명단에서 삭제할까요?',
            style: GoogleFonts.notoSansKr(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(schoolRepositoryProvider).deleteRosterEntry(e.id);
      ref.invalidate(schoolRosterProvider);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(err))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = gradeClass.split('-');
    final title = '${parts[0]}학년 ${parts[1]}반';
    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppColors.teacherNavy)),
              const Spacer(),
              IconButton(
                tooltip: '이 학급 PIN 복사',
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: AppColors.teacherNavy,
                onPressed: () async {
                  final text = entries
                      .map((e) =>
                          '${e.studentNum}번 ${e.name}: ${e.pin}${e.claimed ? ' (가입완료)' : ''}')
                      .join('\n');
                  await Clipboard.setData(
                      ClipboardData(text: '[$title PIN]\n$text'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$title PIN을 복사했어요')),
                    );
                  }
                },
              ),
            ],
          ),
          const Divider(),
          ...entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text('${e.studentNum}번',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ),
                    Expanded(
                      child: Text(e.name,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    if (e.claimed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.studentGreenLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('가입완료',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.studentGreen)),
                      )
                    else
                      Text(e.pin,
                          style: GoogleFonts.robotoMono(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: AppColors.teacherNavy)),
                    IconButton(
                      tooltip: '삭제',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () => _deleteOne(context, ref, e),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
