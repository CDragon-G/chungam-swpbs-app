import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/providers/profile_provider.dart';
import '../../shared/widgets/pbs_card.dart';

// ══════════════════ 모델 ══════════════════

class SupportSettings {
  const SupportSettings({
    required this.windowDays,
    required this.cico,
    required this.tier3,
    required this.tier3Year,
  });
  final int windowDays;
  final int cico;
  final int tier3;

  /// 0 이면 학년도 누적 기준을 쓰지 않는다.
  final int tier3Year;

  static const defaults =
      SupportSettings(windowDays: 30, cico: 3, tier3: 5, tier3Year: 7);

  factory SupportSettings.fromMap(Map<String, dynamic> m) => SupportSettings(
        windowDays: (m['window_days'] as num?)?.toInt() ?? 30,
        cico: (m['cico'] as num?)?.toInt() ?? 3,
        tier3: (m['tier3'] as num?)?.toInt() ?? 5,
        tier3Year: (m['tier3_year'] as num?)?.toInt() ?? 7,
      );
}

class SupportReferral {
  const SupportReferral({
    required this.id,
    required this.status,
    required this.trigger,
    required this.name,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.windowCount,
    required this.yearCount,
    required this.urgentCount,
    required this.lastKodr,
    required this.topPlaces,
    required this.topBehaviors,
    required this.cicoStatus,
    required this.meetingDate,
    required this.createdAt,
  });

  final String id;
  final String status; // open | scheduled | supporting | monitoring | closed
  final String trigger; // kodr_window | kodr_year | manual
  final String name;
  final int? grade;
  final int? classNum;
  final int? studentNum;
  final int windowCount;
  final int yearCount;
  final int urgentCount;
  final DateTime? lastKodr;
  final List<String> topPlaces;
  final List<String> topBehaviors;
  final String? cicoStatus; // active | graduated | stopped | null
  final DateTime? meetingDate;
  final DateTime createdAt;

  String get label => (grade != null && classNum != null && studentNum != null)
      ? '$grade학년 $classNum반 $studentNum번 $name'
      : name;

  static List<String> _strings(dynamic v) =>
      ((v as List?) ?? const []).map((e) => '$e').toList();

  factory SupportReferral.fromMap(Map<String, dynamic> m) => SupportReferral(
        id: m['id'] as String,
        status: (m['status'] as String?) ?? 'open',
        trigger: (m['trigger'] as String?) ?? 'manual',
        name: (m['name'] as String?) ?? '',
        grade: (m['grade'] as num?)?.toInt(),
        classNum: (m['class_num'] as num?)?.toInt(),
        studentNum: (m['student_num'] as num?)?.toInt(),
        windowCount: (m['window_count'] as num?)?.toInt() ?? 0,
        yearCount: (m['year_count'] as num?)?.toInt() ?? 0,
        urgentCount: (m['urgent_count'] as num?)?.toInt() ?? 0,
        lastKodr: DateTime.tryParse(m['last_kodr'] as String? ?? ''),
        topPlaces: _strings(m['top_places']),
        topBehaviors: _strings(m['top_behaviors']),
        cicoStatus: m['cico_status'] as String?,
        meetingDate: DateTime.tryParse(m['meeting_date'] as String? ?? ''),
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

const _statusLabels = {
  'open': '안건 상정 대기',
  'scheduled': '회의 예정',
  'supporting': '학맞통 지원 중',
  'monitoring': '관찰 유지',
  'closed': '종결',
};

Color _statusColor(String s) => switch (s) {
      'open' => const Color(0xFFDC2626),
      'scheduled' => const Color(0xFFD97706),
      'supporting' => const Color(0xFF7C3AED),
      'monitoring' => const Color(0xFF2563EB),
      _ => AppColors.textTertiary,
    };

String _ymd(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

// ══════════════════ 데이터 ══════════════════

Map<String, dynamic> _okOrThrow(dynamic res, String fallback) {
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) throw StateError(m['error'] as String? ?? fallback);
  return m;
}

final supportSettingsProvider =
    FutureProvider.autoDispose<SupportSettings>((ref) async {
  try {
    final res = await SupabaseService.client.rpc('get_support_settings');
    if (res == null) return SupportSettings.defaults;
    return SupportSettings.fromMap(Map<String, dynamic>.from(res as Map));
  } catch (_) {
    return SupportSettings.defaults; // 059 이전 서버
  }
});

final supportIncludeClosedProvider = StateProvider.autoDispose<bool>((_) => false);

final supportReferralsProvider =
    FutureProvider.autoDispose<List<SupportReferral>>((ref) async {
  final includeClosed = ref.watch(supportIncludeClosedProvider);
  final res = await SupabaseService.client.rpc('support_referral_list',
      params: {'p_include_closed': includeClosed});
  final m = _okOrThrow(res, '안건을 불러오지 못했어요');
  return ((m['items'] as List?) ?? const [])
      .map((e) => SupportReferral.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

// ══════════════════ 화면 ══════════════════

/// 🧩 학맞통 연계 안건 — 관리자(리더십팀)용.
///
/// K-ODR 이 기준에 닿으면 여기에 자동으로 올라온다. 회의에 가져갈 숫자
/// (최근 건수 · 학년도 누적 · 자주 일어난 장소와 행동 · CICO 이력)를 한눈에 본다.
///
/// 회의 내용은 적지 않는다. 학맞통 대상 여부는 매우 민감한 정보라
/// 상태와 회의 날짜만 두고, 회의록은 학교의 공식 기록에 남긴다.
class SupportReferralScreen extends ConsumerWidget {
  const SupportReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('🧩 학맞통 연계 안건',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      ),
      body: !isAdmin
          ? Center(
              child: Text('관리자 선생님만 볼 수 있어요',
                  maxLines: 1,
                  style:
                      GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(supportReferralsProvider);
                ref.invalidate(supportSettingsProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(AppSizes.lg),
                children: const [
                  _TierGuide(),
                  SizedBox(height: AppSizes.md),
                  _SettingsCard(),
                  SizedBox(height: AppSizes.md),
                  _ReferralList(),
                  SizedBox(height: AppSizes.xxxl),
                ],
              ),
            ),
    );
  }
}

/// 3단계 지원 구조를 한 장으로.
class _TierGuide extends ConsumerWidget {
  const _TierGuide();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(supportSettingsProvider).value ?? SupportSettings.defaults;

    Widget row(String tier, String title, String rule, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tier,
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: Text(title,
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: Text(rule,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
        );

    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('K-ODR 기록이 지원으로 이어지는 길',
              maxLines: 1,
              style: GoogleFonts.notoSansKr(
                  fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          row('Tier 1', '보편 지원', '규칙·자기점검·칭찬 — 모든 학생',
              AppColors.studentGreen),
          row('Tier 2', 'CICO', '최근 ${s.windowDays}일 K-ODR ${s.cico}건 이상',
              const Color(0xFFD97706)),
          row(
              'Tier 3',
              '학맞통 안건',
              s.tier3Year > 0
                  ? '최근 ${s.windowDays}일 ${s.tier3}건 · 학년도 누적 ${s.tier3Year}건'
                  : '최근 ${s.windowDays}일 K-ODR ${s.tier3}건 이상',
              const Color(0xFFDC2626)),
          const SizedBox(height: 8),
          Text(
            'Tier 1 이 튼튼할수록 Tier 3 로 올라오는 학생이 줄어듭니다.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.studentGreen),
          ),
        ],
      ),
    );
  }
}

/// 학교별 기준 조정.
class _SettingsCard extends ConsumerStatefulWidget {
  const _SettingsCard();

  @override
  ConsumerState<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<_SettingsCard> {
  SupportSettings? _draft;
  bool _saving = false;
  bool _open = false;

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _saving = true);
    try {
      final res = await SupabaseService.client.rpc('set_support_settings', params: {
        'p_window_days': d.windowDays,
        'p_cico': d.cico,
        'p_tier3': d.tier3,
        'p_tier3_year': d.tier3Year,
      });
      _okOrThrow(res, '저장하지 못했어요');
      ref.invalidate(supportSettingsProvider);
      if (mounted) {
        setState(() => _open = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기준을 저장했어요. 다음 K-ODR 기록부터 적용돼요.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    try {
      final res = await SupabaseService.client.rpc('scan_support_referrals');
      final m = _okOrThrow(res, '확인하지 못했어요');
      ref.invalidate(supportReferralsProvider);
      if (mounted) {
        final n = (m['added'] as num?)?.toInt() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(n > 0
                ? '지금 기준으로 $n명을 안건에 새로 올렸어요'
                : '지금 기준으로 새로 올릴 학생이 없어요')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  Widget _stepper(String label, String unit, int value, int min, int max,
      ValueChanged<int> onChanged, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                if (hint != null)
                  Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          SizedBox(
            width: 52,
            child: Text(value == 0 && unit == '건' ? '끔' : '$value$unit',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(supportSettingsProvider).value;
    if (current == null) return const SizedBox.shrink();
    final d = _draft ?? current;

    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('우리 학교 연계 기준',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _open = !_open;
                  _draft = current;
                }),
                child: Text(_open ? '닫기' : '조정하기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (_open) ...[
            _stepper('살펴볼 기간', '일', d.windowDays, 7, 90,
                (v) => setState(() => _draft = SupportSettings(
                    windowDays: v, cico: d.cico, tier3: d.tier3, tier3Year: d.tier3Year)),
                hint: '최근 며칠 동안의 K-ODR 을 셀까요'),
            _stepper('CICO 권장', '건', d.cico, 1, 10,
                (v) => setState(() => _draft = SupportSettings(
                    windowDays: d.windowDays, cico: v, tier3: d.tier3, tier3Year: d.tier3Year)),
                hint: '기본 3건'),
            _stepper('학맞통 안건', '건', d.tier3, 2, 20,
                (v) => setState(() => _draft = SupportSettings(
                    windowDays: d.windowDays, cico: d.cico, tier3: v, tier3Year: d.tier3Year)),
                hint: '기본 5건 · 권장 5~7건'),
            _stepper('학년도 누적', '건', d.tier3Year, 0, 60,
                (v) => setState(() => _draft = SupportSettings(
                    windowDays: d.windowDays, cico: d.cico, tier3: d.tier3, tier3Year: v)),
                hint: '기본 7건 · 0 이면 끔'),
            const SizedBox(height: 6),
            Text(
              '참고: PBIS(SWIS) 기준은 한 해 2~5건 Tier 2, 6건 이상 Tier 3 입니다.\n'
              '최근 기간은 몰아서 생긴 위기를, 누적은 꾸준히 이어지는 어려움을 잡습니다.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, height: 1.6, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _draft = SupportSettings.defaults),
                    child: Text('기본값',
                        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teacherNavy),
                    onPressed: _saving ? null : _save,
                    child: Text('저장',
                        style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              '최근 ${current.windowDays}일 · CICO ${current.cico}건 · 학맞통 ${current.tier3}건'
              '${current.tier3Year > 0 ? ' · 누적 ${current.tier3Year}건' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text('지금 기준으로 전교생 다시 확인',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralList extends ConsumerWidget {
  const _ReferralList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supportReferralsProvider);
    final includeClosed = ref.watch(supportIncludeClosedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('안건 목록',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 15, fontWeight: FontWeight.w900)),
            ),
            FilterChip(
              label: Text('종결 포함',
                  style: GoogleFonts.notoSansKr(fontSize: 12)),
              selected: includeClosed,
              onSelected: (v) =>
                  ref.read(supportIncludeClosedProvider.notifier).state = v,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSizes.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Text(translateError(e),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
          ),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSizes.xl),
                  child: Text(
                    '지금 올라온 안건이 없어요.\n보편 지원이 잘 작동하고 있다는 신호예요.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, height: 1.7, color: AppColors.textSecondary),
                  ),
                )
              : Column(
                  children: [for (final r in items) _ReferralCard(referral: r)],
                ),
        ),
      ],
    );
  }
}

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard({required this.referral});
  final SupportReferral referral;

  Future<void> _update(BuildContext context, WidgetRef ref, String status,
      {DateTime? meeting}) async {
    try {
      final res = await SupabaseService.client.rpc('update_support_referral', params: {
        'p_id': referral.id,
        'p_status': status,
        'p_meeting_date': meeting == null
            ? null
            : '${meeting.year}-${meeting.month.toString().padLeft(2, '0')}-${meeting.day.toString().padLeft(2, '0')}',
      });
      _okOrThrow(res, '바꾸지 못했어요');
      ref.invalidate(supportReferralsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = referral;
    final s = ref.watch(supportSettingsProvider).value ?? SupportSettings.defaults;
    final color = _statusColor(r.status);

    final triggerText = switch (r.trigger) {
      'kodr_window' => '최근 기간 기준',
      'kodr_year' => '학년도 누적 기준',
      _ => '리더십팀 직접 상정',
    };
    final cicoText = switch (r.cicoStatus) {
      'active' => 'CICO 진행 중',
      'graduated' => 'CICO 졸업',
      'stopped' => 'CICO 중단',
      _ => 'CICO 이력 없음',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14.5, fontWeight: FontWeight.w900)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_statusLabels[r.status] ?? r.status,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('$triggerText · 올라온 날 ${_ymd(r.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Stat('최근 ${s.windowDays}일', '${r.windowCount}건'),
                _Stat('학년도 누적', '${r.yearCount}건'),
                if (r.urgentCount > 0) _Stat('개입 필요 표시', '${r.urgentCount}건', alert: true),
                _Stat('CICO', cicoText.replaceFirst('CICO ', '')),
                if (r.lastKodr != null) _Stat('마지막 기록', _ymd(r.lastKodr!)),
              ],
            ),
            if (r.topPlaces.isNotEmpty || r.topBehaviors.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (r.topPlaces.isNotEmpty)
                Text('자주 일어난 곳 · ${r.topPlaces.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary)),
              if (r.topBehaviors.isNotEmpty)
                Text('자주 보인 행동 · ${r.topBehaviors.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textSecondary)),
            ],
            if (r.meetingDate != null) ...[
              const SizedBox(height: 4),
              Text('회의 ${_ymd(r.meetingDate!)}',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFD97706))),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: r.status,
                      isExpanded: true,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, color: AppColors.textPrimary),
                      items: [
                        for (final e in _statusLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        if (v != null && v != r.status) _update(context, ref, v);
                      },
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: r.meetingDate ?? now,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null && context.mounted) {
                      _update(context, ref,
                          r.status == 'open' ? 'scheduled' : r.status,
                          meeting: picked);
                    }
                  },
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text('회의 날짜',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.alert = false});
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFFEE2E2) : AppColors.borderLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $value',
          maxLines: 1,
          style: GoogleFonts.notoSansKr(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: alert ? const Color(0xFFB91C1C) : AppColors.textSecondary)),
    );
  }
}
