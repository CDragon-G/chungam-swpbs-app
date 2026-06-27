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
          labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: '명단 업로드'),
            Tab(text: 'PIN 조회'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _UploadTab(),
          _PinListTab(),
        ],
      ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(schoolRosterProvider);
    return rosterAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(translateError(e))),
      data: (roster) {
        if (roster.isEmpty) {
          return Center(
            child: Text('등록된 명단이 없어요.\n"명단 업로드" 탭에서 먼저 등록하세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
          );
        }
        // 학급별 그룹화
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
            for (final k in keys) ...[
              _ClassPinCard(
                gradeClass: k,
                entries: groups[k]!,
              ),
              const SizedBox(height: AppSizes.md),
            ],
          ],
        );
      },
    );
  }
}

class _ClassPinCard extends StatelessWidget {
  const _ClassPinCard({required this.gradeClass, required this.entries});
  final String gradeClass;
  final List<RosterEntry> entries;

  @override
  Widget build(BuildContext context) {
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
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
