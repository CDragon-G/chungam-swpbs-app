import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../school/models/roster_entry.dart';

/// 진급 계획 — 서버가 세운 것을 그대로 받는다.
class PromotionPlan {
  const PromotionPlan({
    required this.moves,
    required this.newcomers,
    required this.leaving,
    required this.ambiguous,
  });

  final List<PlanRow> moves;
  final List<PlanRow> newcomers;
  final List<PlanRow> leaving;
  final List<PlanRow> ambiguous;

  bool get isEmpty =>
      moves.isEmpty && newcomers.isEmpty && leaving.isEmpty;

  /// 동명이인이 남아 있으면 실행할 수 없다. 그 학생들만 빼고 돌리면
  /// 자리가 어긋나 다른 학생의 이동까지 막힌다.
  bool get isBlocked => ambiguous.isNotEmpty;

  static List<PlanRow> _rows(dynamic v) => ((v as List?) ?? const [])
      .map((e) => PlanRow.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  factory PromotionPlan.fromMap(Map<String, dynamic> m) => PromotionPlan(
        moves: _rows(m['moves']),
        newcomers: _rows(m['new']),
        leaving: _rows(m['leaving']),
        ambiguous: _rows(m['ambiguous']),
      );
}

class PlanRow {
  const PlanRow({
    required this.name,
    this.from,
    this.to,
    this.joined = false,
    this.reason,
    this.grade,
  });

  final String name;
  final String? from; // '2-3-5'
  final String? to;
  final bool joined; // 이미 가입한 학생인가
  final String? reason;
  final int? grade;

  static String _slot(String? s) {
    if (s == null) return '';
    final p = s.split('-');
    if (p.length != 3) return s;
    return '${p[0]}학년 ${p[1]}반 ${p[2]}번';
  }

  String get fromLabel => _slot(from);
  String get toLabel => _slot(to);

  factory PlanRow.fromMap(Map<String, dynamic> m) => PlanRow(
        name: (m['name'] as String?) ?? '',
        from: m['from'] as String?,
        to: m['to'] as String?,
        joined: m['joined'] == true,
        reason: m['reason'] as String?,
        grade: (m['grade'] as num?)?.toInt(),
      );
}

/// 🎓 새 학년도 진급 처리.
///
/// 명단의 고유키는 '자리'(학년·반·번호)라서, 새 명렬표를 그냥 올리면
/// 이미 가입한 학생은 작년 학번에 그대로 남고 신입생은 잠긴 자리 때문에
/// 가입조차 못 한다. 여기서는 자리를 새로 만드는 대신 사람을 옮긴다.
///
/// 되돌리기 어려운 작업이라 반드시 미리보기를 거친다.
class RosterPromotionScreen extends ConsumerStatefulWidget {
  const RosterPromotionScreen({super.key});

  @override
  ConsumerState<RosterPromotionScreen> createState() =>
      _RosterPromotionScreenState();
}

class _RosterPromotionScreenState extends ConsumerState<RosterPromotionScreen> {
  final _controller = TextEditingController();
  List<RosterDraftRow> _parsed = [];
  List<String> _parseErrors = [];
  PromotionPlan? _plan;
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final (rows, errors) = RosterParser.parse(_controller.text);
    setState(() {
      _parsed = rows;
      _parseErrors = errors;
      _plan = null;
      _result = null;
    });
  }

  Future<void> _preview() async {
    final schoolId = ref.read(profileProvider).value?.schoolId;
    if (schoolId == null || _parsed.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final res = await SupabaseService.client.rpc(
        'promote_roster_preview',
        params: {
          'p_school_id': schoolId,
          'p_rows': _parsed.map((r) => r.toJson()).toList(),
        },
      );
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) {
        throw StateError(m['error'] as String? ?? '미리보기를 만들지 못했어요');
      }
      setState(() => _plan = PromotionPlan.fromMap(m));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    final schoolId = ref.read(profileProvider).value?.schoolId;
    if (plan == null || schoolId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('진급 처리를 실행할까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '${plan.moves.length}명 이동 · ${plan.newcomers.length}명 신규 · '
          '${plan.leaving.length}명 졸업·전출\n\n'
          '되돌리기 어렵습니다. 미리보기 내용을 한 번 더 확인해 주세요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherNavy),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('실행',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await SupabaseService.client.rpc(
        'promote_roster_apply',
        params: {
          'p_school_id': schoolId,
          'p_rows': _parsed.map((r) => r.toJson()).toList(),
        },
      );
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) {
        throw StateError(m['error'] as String? ?? '처리하지 못했어요');
      }
      setState(() {
        _result = '완료 — ${m['moved']}명 이동, ${m['added']}명 신규 등록, '
            '${m['left']}명 졸업·전출 처리';
        _plan = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('새 학년도 진급 처리',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          PbsCard(
            color: const Color(0xFFFEF3C7),
            child: Text(
              '새 학년도 전교생 명렬표를 붙여넣으세요.\n'
              '이름이 같고 학년이 정확히 하나 오른 학생은 자리를 그대로 옮깁니다. '
              'PIN도 그대로라 다시 가입할 필요가 없습니다.\n\n'
              '명렬표에 없는 학생은 졸업·전출로 처리되고, '
              '새 이름은 신입생으로 등록되어 새 PIN을 받습니다.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5,
                  height: 1.7,
                  color: const Color(0xFF92400E)),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _controller,
            maxLines: 8,
            onChanged: (_) => _parse(),
            style: GoogleFonts.notoSansKr(fontSize: 13),
            decoration: InputDecoration(
              hintText: '1\t1\t1\t김민수\n1\t1\t2\t이서연\n...\n'
                  '(엑셀에서 학년·반·번호·이름 열을 복사해 붙여넣기)',
              hintStyle: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textTertiary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_parseErrors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('읽지 못한 줄 ${_parseErrors.length}개 — ${_parseErrors.first}',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.danger)),
          ],
          const SizedBox(height: AppSizes.md),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherNavy,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: (_parsed.isEmpty || _busy) ? null : _preview,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('미리보기 (${_parsed.length}명)',
                    style:
                        GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
          if (_result != null) ...[
            const SizedBox(height: AppSizes.md),
            PbsCard(
              color: const Color(0xFFF0FDF4),
              child: Text('✅ $_result',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      height: 1.6,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF166534))),
            ),
          ],
          if (plan != null) ...[
            const SizedBox(height: AppSizes.lg),
            if (plan.ambiguous.isNotEmpty)
              _Section(
                title: '⚠️ 사람이 확인해야 해요 (${plan.ambiguous.length})',
                color: const Color(0xFFFEF2F2),
                rows: plan.ambiguous
                    .map((r) => _Line(
                          left: r.name,
                          right: r.grade != null ? '${r.grade}학년' : '',
                          note: r.reason,
                        ))
                    .toList(),
                footer: '이 학생들이 정리되기 전에는 진급 처리를 실행할 수 없습니다. '
                    '학생 관리 화면에서 이 학생들의 학년·반·번호를 먼저 맞춰 주세요. '
                    '몇 명만 빼고 돌리면 자리가 어긋나 다른 학생의 이동까지 막힙니다.',
              ),
            _Section(
              title: '↗️ 진급 (${plan.moves.length})',
              color: const Color(0xFFF0FDF4),
              rows: plan.moves
                  .map((r) => _Line(
                        left: r.name + (r.joined ? '' : '  (미가입)'),
                        right: '${r.fromLabel}  →  ${r.toLabel}',
                      ))
                  .toList(),
            ),
            _Section(
              title: '🌱 신입생 (${plan.newcomers.length})',
              color: const Color(0xFFEFF6FF),
              rows: plan.newcomers
                  .map((r) => _Line(left: r.name, right: r.toLabel))
                  .toList(),
              footer: '새 PIN이 발급됩니다. 명단 화면에서 인쇄해 나눠주세요.',
            ),
            _Section(
              title: '🎓 졸업·전출 (${plan.leaving.length})',
              color: const Color(0xFFF8FAFC),
              rows: plan.leaving
                  .map((r) => _Line(
                        left: r.name + (r.joined ? '' : '  (미가입)'),
                        right: r.fromLabel,
                      ))
                  .toList(),
              footer: '기록과 포인트는 그대로 보관됩니다. '
                  '다만 참여율 계산에서는 빠지고, 자기점검을 할 수 없게 됩니다.',
            ),
            const SizedBox(height: AppSizes.md),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 15)),
              onPressed:
                  (_busy || plan.isEmpty || plan.isBlocked) ? null : _apply,
              child: Text(
                  plan.isBlocked ? '동명이인을 먼저 정리해 주세요' : '이대로 진급 처리하기',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ],
          const SizedBox(height: AppSizes.xxxl),
        ],
      ),
    );
  }
}

class _Line {
  const _Line({required this.left, required this.right, this.note});
  final String left;
  final String right;
  final String? note;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.color,
    required this.rows,
    this.footer,
  });

  final String title;
  final Color color;
  final List<_Line> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final shown = rows.take(60).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: PbsCard(
        color: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13.5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...shown.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l.left,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Text(l.right,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                      if (l.note != null)
                        Text(l.note!,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11, color: AppColors.danger)),
                    ],
                  ),
                )),
            if (rows.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('... 외 ${rows.length - shown.length}명',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11.5, color: AppColors.textTertiary)),
              ),
            if (footer != null) ...[
              const SizedBox(height: 8),
              Text(footer!,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5,
                      height: 1.6,
                      color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
