import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../growth/growth_celebration.dart';
import '../../points/providers/points_provider.dart';
import '../../praise/providers/praise_provider.dart';
import '../../school/providers/school_provider.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _State();
}

class _State extends ConsumerState<StudentListScreen> {
  String _filterGrade = '전체';
  String _filterClass = '전체';
  String _query = '';

  /// 여러 명 선택 모드 — 학급 전체 칭찬용
  bool _multi = false;
  final Set<String> _selected = {};

  void _toggleMulti() => setState(() {
        _multi = !_multi;
        _selected.clear();
      });

  bool _matchesQuery(Map<String, dynamic> s) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase().replaceAll(' ', '');
    final name = (s['nickname'] as String? ?? '').toLowerCase();
    final g = '${s['grade']}', c = '${s['class_num']}', n = '${s['student_num']}';
    return [name, '$g-$c-$n', '$g학년$c반$n번', '$g$c$n', n]
        .any((x) => x.contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(schoolStudentsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: (!_multi || _selected.isEmpty)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.teacherNavy,
              onPressed: _givePraiseBulk,
              icon: const Icon(Icons.favorite_rounded, color: Colors.white),
              label: Text('${_selected.length}명에게 칭찬',
                  style: GoogleFonts.notoSansKr(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '학생 칭찬하기',
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              _multi
                  ? '여러 명을 골라 한 번에 칭찬해요'
                  : '학생을 검색해 칭찬 한마디 + 50P + 배지',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _toggleMulti,
            icon: Icon(
                _multi
                    ? Icons.close_rounded
                    : Icons.checklist_rounded,
                size: 19,
                color: AppColors.teacherNavy),
            label: Text(_multi ? '취소' : '여러 명',
                style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.teacherNavy)),
          ),
        ],
      ),
      body: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (students) {
          final grades = {'전체', for (final s in students) '${s['grade']}학년'};
          // 학년을 고르면 그 학년의 반 목록을 보여준다
          final classes = <String>{
            '전체',
            for (final s in students)
              if (_filterGrade == '전체' ||
                  '${s['grade']}학년' == _filterGrade)
                '${s['class_num']}반',
          };
          final filtered = students
              .where((s) =>
                  (_filterGrade == '전체' ||
                      '${s['grade']}학년' == _filterGrade) &&
                  (_filterClass == '전체' ||
                      '${s['class_num']}반' == _filterClass) &&
                  _matchesQuery(s))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.sm),
                child: TextField(
                  style: GoogleFonts.notoSansKr(fontSize: 14),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: '이름 또는 학번 검색 (예: 신창용, 1-2-10)',
                    hintStyle: GoogleFonts.notoSansKr(
                        fontSize: 13, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                child: Wrap(
                  spacing: 6,
                  children: grades.map((g) {
                    final selected = _filterGrade == g;
                    return ChoiceChip(
                      label: Text(g),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _filterGrade = g;
                        _filterClass = '전체';
                      }),
                      selectedColor: AppColors.teacherNavy,
                      labelStyle: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(color: AppColors.borderLight),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // 반 칩 (반이 둘 이상일 때만)
              if (classes.length > 2)
                Padding(
                  padding: const EdgeInsets.only(
                      left: AppSizes.lg, right: AppSizes.lg, top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: classes.map((c) {
                      final selected = _filterClass == c;
                      return ChoiceChip(
                        label: Text(c),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _filterClass = c),
                        selectedColor: AppColors.studentGreen,
                        labelStyle: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : AppColors.textPrimary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: BorderSide(color: AppColors.borderLight),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // 여러 명 선택 모드: 전체 선택 바
              if (_multi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.lg, AppSizes.sm, AppSizes.lg, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.teacherNavyLight,
                      borderRadius:
                          BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: filtered.isNotEmpty &&
                              filtered.every((s) =>
                                  _selected.contains(s['user_id'])),
                          tristate: false,
                          activeColor: AppColors.teacherNavy,
                          onChanged: (v) => setState(() {
                            final ids = filtered
                                .map((s) => s['user_id'] as String);
                            if (v == true) {
                              _selected.addAll(ids);
                            } else {
                              _selected.removeAll(ids);
                            }
                          }),
                        ),
                        Expanded(
                          child: Text(
                            _filterClass == '전체'
                                ? '보이는 학생 모두 선택 (${filtered.length}명)'
                                : '$_filterGrade $_filterClass 모두 선택 (${filtered.length}명)',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.teacherNavy),
                          ),
                        ),
                        if (_selected.isNotEmpty)
                          Text('${_selected.length}명 선택됨',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSizes.sm),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: PbsCard(
                        color: _multi && _selected.contains(s['user_id'])
                            ? AppColors.teacherNavyLight
                            : null,
                        onTap: () {
                          if (!_multi) {
                            _showStudentMenu(s);
                            return;
                          }
                          setState(() {
                            final id = s['user_id'] as String;
                            _selected.contains(id)
                                ? _selected.remove(id)
                                : _selected.add(id);
                          });
                        },
                        child: Row(
                          children: [
                            if (_multi)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  _selected.contains(s['user_id'])
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: _selected.contains(s['user_id'])
                                      ? AppColors.teacherNavy
                                      : AppColors.textTertiary,
                                  size: 24,
                                ),
                              ),
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.teacherNavy,
                              child: Text(
                                ((s['nickname'] as String).characters.isEmpty
                                    ? '?'
                                    : (s['nickname'] as String).characters.first),
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['nickname'] as String,
                                    style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${s['grade']}학년 ${s['class_num']}반 ${s['student_num']}번',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _StudentPoints(userId: s['user_id'] as String),
                            const SizedBox(width: 2),
                            // 칭찬 바로가기 (가장 자주 쓰는 동작이라 직접 노출)
                            IconButton(
                              icon: const Icon(Icons.favorite_rounded,
                                  color: AppColors.studentGreen),
                              tooltip: '칭찬하기',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _givePraise(s),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStudentMenu(Map<String, dynamic> student) {
    final name = student['nickname'] as String;
    final label =
        '$name (${student['grade']}학년 ${student['class_num']}반 ${student['student_num']}번)';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.favorite_rounded,
                  color: AppColors.studentGreen),
              title: Text(
                '칭찬하기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '칭찬 메시지 전송 + 50P 적립 + 칭찬 배지',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _givePraise(student);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded,
                  color: AppColors.teacherNavy),
              title: Text(
                '비밀번호 초기화',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '임시 비밀번호를 발급해 학생에게 전달하세요',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _resetPassword(student);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alternate_email_rounded,
                  color: AppColors.textSecondary),
              title: Text(
                '로그인 이메일 확인',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '이메일을 잊은 학생에게 알려주세요',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showStudentEmail(student);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 학생 로그인 이메일 조회 (이메일 찾기 지원 — 같은 학교 교사만, 서버 검증).
  Future<void> _showStudentEmail(Map<String, dynamic> student) async {
    final name = student['nickname'] as String;
    try {
      final email = await ref
          .read(authRepositoryProvider)
          .getStudentEmail(student['id'] as String);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$name 학생의 로그인 이메일',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                email,
                style: GoogleFonts.robotoMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.teacherNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '비밀번호도 잊었다면 "비밀번호 초기화"를 함께 해주세요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('복사', style: GoogleFonts.notoSansKr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('확인', style: GoogleFonts.notoSansKr()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translateError(e))),
      );
    }
  }

  /// 💚 선택한 여러 학생에게 같은 칭찬을 한 번에 보낸다.
  Future<void> _givePraiseBulk() async {
    final ids = _selected.toList();
    final controller = TextEditingController();
    const presets = [
      '오늘 우리 반 정말 멋졌어요!',
      '모두 수업에 열심히 참여했어요',
      '서로 도와주는 모습이 보기 좋았어요',
      '청소를 깔끔하게 해냈어요',
      '약속을 잘 지킨 하루였어요',
    ];
    var sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) {
          Future<void> submit() async {
            final msg = controller.text.trim();
            if (msg.isEmpty) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('칭찬 메시지를 입력해주세요.')),
              );
              return;
            }
            setSt(() => sending = true);
            try {
              final sent = await ref
                  .read(praiseRepositoryProvider)
                  .givePraiseBulk(studentUserIds: ids, message: msg);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (!mounted) return;
              setState(() {
                _selected.clear();
                _multi = false;
              });
              celebrateGrowth(context, ref,
                  headline: '$sent명에게 칭찬을 보냈어요! 💚 (각 +50P)');
            } catch (e) {
              if (!dialogCtx.mounted) return;
              setSt(() => sending = false);
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                SnackBar(content: Text(translateError(e))),
              );
            }
          }

          return AlertDialog(
            title: Text('${ids.length}명에게 칭찬하기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('선택한 학생 모두에게 같은 한마디가 전달돼요.',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSizes.md),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: presets
                          .map((t) => ActionChip(
                                label: Text(t,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () =>
                                    setSt(() => controller.text = t),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: AppSizes.md),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      style: GoogleFonts.notoSansKr(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '칭찬 한마디를 적어주세요',
                        hintStyle: GoogleFonts.notoSansKr(
                            fontSize: 13, color: AppColors.textTertiary),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    sending ? null : () => Navigator.pop(dialogCtx),
                child: Text('취소',
                    style: GoogleFonts.notoSansKr(
                        color: AppColors.textTertiary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teacherNavy),
                onPressed: sending ? null : submit,
                child: Text(sending ? '보내는 중...' : '보내기',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _givePraise(Map<String, dynamic> student) async {
    final name = student['nickname'] as String;
    final controller = TextEditingController();
    // 빠른 선택용 칭찬 예시
    const presets = [
      '오늘 정말 잘했어요!',
      '친구를 도와주는 모습이 멋졌어요',
      '수업에 열심히 참여했어요',
      '약속을 잘 지켰어요',
      '예의 바른 모습이 보기 좋았어요',
    ];
    var sending = false;

    // 별도 로딩 다이얼로그 없이, 입력 다이얼로그 내부에서 전송을 처리한다.
    // (로딩 다이얼로그가 mounted 문제로 닫히지 않아 검은 화면이 되던 문제 방지)
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) {
          Future<void> submit() async {
            final msg = controller.text.trim();
            if (msg.isEmpty) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('칭찬 메시지를 입력해주세요.')),
              );
              return;
            }
            setSt(() => sending = true);
            try {
              final count = await ref.read(praiseRepositoryProvider).givePraise(
                    studentUserId: student['user_id'] as String,
                    message: msg,
                  );
              if (dialogCtx.mounted) Navigator.pop(dialogCtx); // 다이얼로그 닫기
              if (!mounted) return;
              celebrateGrowth(context, ref,
                  headline:
                      '$name 학생에게 칭찬을 보냈어요! 💚 (누적 $count회, +50P)');
            } catch (e) {
              if (!dialogCtx.mounted) return;
              setSt(() => sending = false);
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                SnackBar(content: Text(translateError(e))),
              );
            }
          }

          return AlertDialog(
            title: Text('$name 학생 칭찬하기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('칭찬 메시지를 입력하거나 아래에서 골라주세요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 2,
                    maxLength: 100,
                    enabled: !sending,
                    style: GoogleFonts.notoSansKr(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '예: 오늘 발표를 정말 잘했어요!',
                      hintStyle: GoogleFonts.notoSansKr(
                          fontSize: 13, color: AppColors.textTertiary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets
                        .map((p) => ActionChip(
                              label: Text(p,
                                  style:
                                      GoogleFonts.notoSansKr(fontSize: 11)),
                              onPressed: sending
                                  ? null
                                  : () => setSt(() => controller.text = p),
                              backgroundColor: AppColors.studentGreenLight,
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogCtx),
                child: Text('취소',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: sending ? null : submit,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('칭찬 보내기',
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                            color: AppColors.studentGreen)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> student) async {
    final name = student['nickname'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('비밀번호 초기화',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '$name 학생의 비밀번호를\n임시 비밀번호로 초기화할까요?\n\n'
          '초기화 후 임시 비밀번호를 학생에게 전달하면,\n'
          '학생이 그 비밀번호로 로그인할 수 있어요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('초기화',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w800,
                    color: AppColors.teacherNavy)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 임시 비번 생성: 읽기 쉬운 8자리 (혼동 문자 제외)
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final tempPw = List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(authRepositoryProvider).resetStudentPassword(
            profileId: student['id'] as String,
            newPassword: tempPw,
          );
      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기
      // 임시 비번 표시
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('초기화 완료',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name 학생의 임시 비밀번호예요.\n학생에게 전달해주세요.',
                style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSizes.md),
                decoration: BoxDecoration(
                  color: AppColors.teacherNavyLight,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: AppColors.teacherNavy),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tempPw,
                      style: GoogleFonts.robotoMono(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: AppColors.teacherNavy,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          color: AppColors.teacherNavy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: tempPw));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('임시 비밀번호를 복사했어요')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '* 학생은 이 비밀번호로 로그인할 수 있어요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
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
      Navigator.pop(context); // 로딩 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translateError(e))),
      );
    }
  }
}

class _StudentPoints extends ConsumerWidget {
  const _StudentPoints({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(
      FutureProvider<int>((ref) async =>
          ref.read(pointsRepositoryProvider).userBalance(userId)),
    );
    return balanceAsync.maybeWhen(
      data: (p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.studentGreenLight,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${NumberFormat('#,###').format(p)}P',
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.studentGreen,
          ),
        ),
      ),
      orElse: () => const SizedBox(width: 40, height: 20),
    );
  }
}
