import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../school/providers/school_provider.dart';

/// 🔑 학생 로그인 도움 — 이메일을 잊었거나 비밀번호를 잊은 학생을 위해.
///
/// 이 기능은 학생 목록 화면에도 있었지만 찾기 어려웠다. 학생이 로그인하지 못해
/// 교무실에 찾아온 순간에 바로 쓸 수 있도록 대시보드 바로가기에서 열리는
/// 한 화면으로 따로 뺐다.
///
/// 서버가 권한을 확인한다 — 같은 학교 학생만, 교사 계정만.
class AccountHelpScreen extends ConsumerStatefulWidget {
  const AccountHelpScreen({super.key});

  @override
  ConsumerState<AccountHelpScreen> createState() => _AccountHelpScreenState();
}

class _AccountHelpScreenState extends ConsumerState<AccountHelpScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 이름, '2-3', '2-3-15', 학번('20315') 으로 찾는다.
  bool _matches(Map<String, dynamic> s) {
    final q = _query.trim();
    if (q.isEmpty) return false;
    final name = (s['nickname'] as String?) ?? '';
    if (name.contains(q)) return true;

    final nums = RegExp(r'\d+').allMatches(q).map((m) => m.group(0)!).toList();
    final letters = q.replaceAll(RegExp(r'[\d\s\-./학년반번]'), '');
    if (letters.isNotEmpty || nums.isEmpty) return false;

    final g = (s['grade'] as num?)?.toInt();
    final c = (s['class_num'] as num?)?.toInt();
    final n = (s['student_num'] as num?)?.toInt();

    if (nums.length == 1 && (nums[0].length == 4 || nums[0].length == 5)) {
      final d = nums[0];
      final cc = d.length == 5 ? d.substring(1, 3) : d.substring(1, 2);
      return g == int.parse(d[0]) &&
          c == int.parse(cc) &&
          n == int.parse(d.substring(d.length - 2));
    }
    if (g != int.parse(nums[0])) return false;
    if (nums.length > 1 && c != int.parse(nums[1])) return false;
    if (nums.length > 2 && n != int.parse(nums[2])) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(schoolStudentsProvider).value ?? const [];
    final hits = students.where(_matches).take(30).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/teacher/dashboard'),
        ),
        title: Text('학생 로그인 도움',
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          PbsCard(
            color: AppColors.teacherNavyLight,
            child: Text(
              '로그인하지 못하는 학생을 도와줍니다.\n'
              '· 이메일을 잊었다 → 가입한 이메일을 확인해 알려주세요\n'
              '· 비밀번호를 잊었다 → 임시 비밀번호를 발급해 알려주세요\n'
              '우리 학교 학생만 보이고, 기록은 서버에 남습니다.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5, height: 1.7, color: AppColors.teacherNavy),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.notoSansKr(fontSize: 14),
            decoration: InputDecoration(
              hintText: '학생 이름 · 2-3 · 2-3-15 · 20315',
              hintMaxLines: 1,
              hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 13, color: AppColors.textTertiary),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textSecondary),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '지우기',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          if (_query.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '찾을 학생의 이름이나 학년·반·번호를 입력해주세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, color: AppColors.textTertiary),
              ),
            )
          else if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '찾는 학생이 없어요.\n아직 가입하지 않은 학생일 수 있어요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13, height: 1.7, color: AppColors.textTertiary),
              ),
            )
          else
            for (final s in hits) _StudentCard(student: s),
          const SizedBox(height: AppSizes.xxxl),
        ],
      ),
    );
  }
}

class _StudentCard extends ConsumerStatefulWidget {
  const _StudentCard({required this.student});
  final Map<String, dynamic> student;

  @override
  ConsumerState<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends ConsumerState<_StudentCard> {
  String? _email;
  String? _tempPassword;
  bool _busy = false;

  String get _name => (widget.student['nickname'] as String?) ?? '이름 없음';
  String get _profileId => widget.student['id'] as String;

  String get _label {
    final g = widget.student['grade'];
    final c = widget.student['class_num'];
    final n = widget.student['student_num'];
    return (g == null || c == null) ? '' : '$g학년 $c반 ${n ?? '-'}번';
  }

  /// 읽어주기 쉬운 임시 비밀번호. 헷갈리는 글자(0/O, 1/l)는 뺀다.
  static String _makeTempPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _loadEmail() async {
    setState(() => _busy = true);
    try {
      final email =
          await ref.read(authRepositoryProvider).getStudentEmail(_profileId);
      if (mounted) setState(() => _email = email);
    } catch (e) {
      _snack(translateError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_name 학생 비밀번호 초기화',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '임시 비밀번호를 새로 만듭니다.\n'
          '지금 쓰던 비밀번호는 쓸 수 없게 되니, 임시 비밀번호를 꼭 학생에게 알려주세요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소', style: GoogleFonts.notoSansKr())),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('초기화', style: GoogleFonts.notoSansKr()),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final pw = _makeTempPassword();
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetStudentPassword(
            profileId: _profileId,
            newPassword: pw,
          );
      if (mounted) setState(() => _tempPassword = pw);
    } catch (e) {
      _snack(translateError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 15, fontWeight: FontWeight.w900)),
                      Text(_label,
                          maxLines: 1,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 11.5, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 10),
            if (_email != null) ...[
              _CopyRow(
                label: '가입한 이메일',
                value: _email!,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _email!));
                  _snack('이메일을 복사했어요');
                },
              ),
              const SizedBox(height: 8),
            ],
            if (_tempPassword != null) ...[
              _CopyRow(
                label: '임시 비밀번호',
                value: _tempPassword!,
                highlight: true,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _tempPassword!));
                  _snack('임시 비밀번호를 복사했어요');
                },
              ),
              const SizedBox(height: 4),
              Text(
                '학생에게 직접 알려주세요. 로그인한 뒤 바꾸면 됩니다.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _email != null ? null : _loadEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.teacherNavy,
                      side: const BorderSide(color: AppColors.teacherNavy),
                    ),
                    icon: const Icon(Icons.alternate_email_rounded, size: 17),
                    label: Text('이메일 확인',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _resetPassword,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teacherNavy),
                    icon: const Icon(Icons.lock_reset_rounded, size: 17),
                    label: Text('비밀번호 초기화',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.highlight = false,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF7ED) : AppColors.borderLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textSecondary)),
                SelectableText(
                  value,
                  maxLines: 1,
                  style: GoogleFonts.robotoMono(
                    fontSize: highlight ? 19 : 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: highlight ? 2 : 0,
                    color: highlight
                        ? const Color(0xFFB45309)
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '복사',
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: AppColors.textSecondary,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
