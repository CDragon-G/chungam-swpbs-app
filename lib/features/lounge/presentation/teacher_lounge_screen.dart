import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../models/lounge_models.dart';
import '../providers/lounge_provider.dart';

/// 🎁 교사 라운지 — SWPBS에 기여한 만큼 쌓이는 교사 포인트로
/// 강화물(기프티콘 등)을 교환하고, 동료의 재능기부 클래스에 참여한다.
class TeacherLoungeScreen extends ConsumerStatefulWidget {
  const TeacherLoungeScreen({super.key});

  @override
  ConsumerState<TeacherLoungeScreen> createState() =>
      _TeacherLoungeScreenState();
}

class _TeacherLoungeScreenState extends ConsumerState<TeacherLoungeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminTeacher ?? false;
    final balance = ref.watch(teacherPointBalanceProvider).value ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('🎁 교사 라운지',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: '포인트 얻는 방법',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _showHowToSheet(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // 내 포인트 카드
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.teacherNavy, Color(0xFF33518A)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text('🌱 내 포인트',
                        style: GoogleFonts.notoSansKr(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${NumberFormat('#,###').format(balance)}P',
                        style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              TabBar(
                controller: _tc,
                indicatorColor: AppColors.teacherNavy,
                labelColor: AppColors.teacherNavy,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle:
                    GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: '강화물'),
                  Tab(text: '원데이클래스'),
                  Tab(text: '내역'),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: switch (_tc.index) {
        0 when isAdmin => FloatingActionButton.extended(
            backgroundColor: AppColors.teacherNavy,
            onPressed: () => _showAddItemSheet(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text('강화물 등록',
                style: GoogleFonts.notoSansKr(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        1 => FloatingActionButton.extended(
            backgroundColor: AppColors.primary,
            onPressed: () => _showOpenClassSheet(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text('클래스 열기',
                style: GoogleFonts.notoSansKr(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        _ => null,
      },
      body: TabBarView(
        controller: _tc,
        children: [
          _RewardsTab(isAdmin: isAdmin, balance: balance),
          _ClassesTab(balance: balance),
          _HistoryTab(isAdmin: isAdmin),
        ],
      ),
    );
  }

  /// 포인트 획득 안내 시트.
  void _showHowToSheet(BuildContext context) {
    const rows = [
      ('🤝 CICO 일일 점검', '+10P', '하루 5건까지'),
      ('✍️ K-ODR 작성', '+8P', '하루 3건까지'),
      ('🍽️ 수업맛집 투표', '+3P', '주간 투표 수만큼'),
      ('⚡ 초성 퀴즈 정답', '+3P', '하루 1회'),
      ('💚 칭찬 보내기', '+2P', '하루 5회까지'),
      ('🎓 클래스 개설 확정', '+15P', '최소 인원 도달 시'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🌱 포인트는 이렇게 쌓여요',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('SWPBS 활동이 곧 포인트예요. 정성이 드는 활동일수록 더 크게!',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(r.$1,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700))),
                        Text(r.$2,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary)),
                        const SizedBox(width: 10),
                        Text(r.$3,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11.5,
                                color: AppColors.textTertiary)),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// (관리자) 강화물 등록 시트.
  void _showAddItemSheet(BuildContext context) {
    final name = TextEditingController();
    final desc = TextEditingController();
    final cost = TextEditingController(text: '30');
    final stock = TextEditingController(text: '5');
    bool unlimited = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: AppSizes.xl,
              right: AppSizes.xl,
              top: AppSizes.xl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('🎁 새 강화물 등록',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('예: 스타벅스 기프티콘, 조기 퇴근 우선권, 주차 명당 1주',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12, color: AppColors.textTertiary)),
              const SizedBox(height: 12),
              _field(name, '강화물 이름'),
              const SizedBox(height: 8),
              _field(desc, '설명 (선택)'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _field(cost, '포인트',
                        keyboard: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: unlimited
                        ? const SizedBox()
                        : _field(stock, '재고',
                            keyboard: TextInputType.number)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('재고 무제한',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                value: unlimited,
                onChanged: (v) => setSheet(() => unlimited = v),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
                onPressed: () async {
                  final schoolId =
                      ref.read(profileProvider).value?.schoolId;
                  final c = int.tryParse(cost.text.trim());
                  if (schoolId == null ||
                      name.text.trim().isEmpty ||
                      c == null ||
                      c <= 0) {
                    return;
                  }
                  await ref.read(loungeRepositoryProvider).addItem(
                        schoolId: schoolId,
                        name: name.text.trim(),
                        description: desc.text.trim().isEmpty
                            ? null
                            : desc.text.trim(),
                        costPoints: c,
                        stock: unlimited
                            ? null
                            : int.tryParse(stock.text.trim()) ?? 1,
                      );
                  invalidateLounge(ref);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('등록',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 클래스 개설 시트 — 재능기부 원데이클래스.
  void _showOpenClassSheet(BuildContext context) {
    final title = TextEditingController();
    final desc = TextEditingController();
    final cost = TextEditingController(text: '10');
    final minP = TextEditingController(text: '3');
    final maxP = TextEditingController();
    final dur = TextEditingController(text: '60');
    final loc = TextEditingController();
    DateTime? when;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: AppSizes.xl,
              right: AppSizes.xl,
              top: AppSizes.xl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSizes.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('🎓 재능기부 클래스 열기',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('예: 배드민턴 15분 레슨, 핸드드립 커피 클래스, 뜨개질 입문',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 12),
                _field(title, '클래스 이름'),
                const SizedBox(height: 8),
                _field(desc, '소개 (선택)'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _field(cost, '참가 포인트',
                          keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _field(dur, '소요(분)',
                          keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _field(minP, '최소 인원',
                          keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _field(maxP, '최대 인원 (선택)',
                          keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                _field(loc, '장소 (선택)'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                      when == null
                          ? '일시 선택 (선택)'
                          : DateFormat('M월 d일 (E) HH:mm', 'ko').format(when!),
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 180)),
                    );
                    if (d == null || !ctx.mounted) return;
                    final t = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 15, minute: 30));
                    setSheet(() => when = DateTime(d.year, d.month, d.day,
                        t?.hour ?? 15, t?.minute ?? 30));
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  onPressed: () async {
                    final schoolId =
                        ref.read(profileProvider).value?.schoolId;
                    if (schoolId == null || title.text.trim().isEmpty) return;
                    await ref.read(loungeRepositoryProvider).openClass(
                          schoolId: schoolId,
                          title: title.text.trim(),
                          description: desc.text.trim().isEmpty
                              ? null
                              : desc.text.trim(),
                          costPoints: int.tryParse(cost.text.trim()) ?? 10,
                          minParticipants:
                              int.tryParse(minP.text.trim()) ?? 3,
                          maxParticipants: int.tryParse(maxP.text.trim()),
                          durationMinutes: int.tryParse(dur.text.trim()),
                          scheduledAt: when,
                          location: loc.text.trim().isEmpty
                              ? null
                              : loc.text.trim(),
                        );
                    invalidateLounge(ref);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text('클래스 열기',
                      style:
                          GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        style: GoogleFonts.notoSansKr(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.notoSansKr(fontSize: 13),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      );
}

// ═══════════ 강화물 탭 ═══════════
class _RewardsTab extends ConsumerWidget {
  const _RewardsTab({required this.isAdmin, required this.balance});
  final bool isAdmin;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(teacherRewardItemsProvider);
    return RefreshIndicator(
      onRefresh: () async => invalidateLounge(ref),
      child: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text('$e'))),
        ]),
        data: (items) => items.isEmpty
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      isAdmin
                          ? '아직 강화물이 없어요.\n+ 버튼으로 첫 강화물을 등록해보세요!'
                          : '아직 강화물이 없어요.\nSWPBS 리더십팀이 준비 중이에요 🎁',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary, height: 1.6),
                    ),
                  ),
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: items.length,
                itemBuilder: (_, i) =>
                    _RewardRow(item: items[i], isAdmin: isAdmin, balance: balance),
              ),
      ),
    );
  }
}

class _RewardRow extends ConsumerWidget {
  const _RewardRow(
      {required this.item, required this.isAdmin, required this.balance});
  final TeacherRewardItem item;
  final bool isAdmin;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affordable = balance >= item.costPoints && !item.soldOut;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  if ((item.description ?? '').isNotEmpty)
                    Text(item.description!,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    '${item.costPoints}P · ${item.stock == null ? "무제한" : "재고 ${item.stock}"}',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.teacherNavy),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teacherNavy,
                disabledBackgroundColor: AppColors.borderLight,
              ),
              onPressed: !affordable
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('강화물 교환'),
                          content: Text(
                              '${item.name}\n${item.costPoints}P를 사용해 교환할까요?\n리더십팀 승인 후 지급됩니다.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('취소')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('교환')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      final err = await ref
                          .read(loungeRepositoryProvider)
                          .exchangeItem(item.id);
                      invalidateLounge(ref);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(err ?? '교환 신청 완료! 승인을 기다려주세요 🎉')));
                      }
                    },
              child: Text(item.soldOut ? '품절' : '교환',
                  style:
                      GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
            ),
            if (isAdmin)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 20, color: AppColors.textTertiary),
                onSelected: (v) async {
                  if (v == 'off') {
                    await ref
                        .read(loungeRepositoryProvider)
                        .deactivateItem(item.id);
                    invalidateLounge(ref);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'off', child: Text('내리기')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════ 원데이클래스 탭 ═══════════
class _ClassesTab extends ConsumerWidget {
  const _ClassesTab({required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(teacherClassesProvider);
    return RefreshIndicator(
      onRefresh: () async => invalidateLounge(ref),
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text('$e'))),
        ]),
        data: (classes) => classes.isEmpty
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      '아직 열린 클래스가 없어요.\n나의 취미·재능을 동료와 나눠보세요!\n(예: 배드민턴 레슨, 커피 클래스) 🎓',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                          color: AppColors.textTertiary, height: 1.6),
                    ),
                  ),
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: classes.length,
                itemBuilder: (_, i) => _ClassCard(info: classes[i]),
              ),
      ),
    );
  }
}

class _ClassCard extends ConsumerWidget {
  const _ClassCard({required this.info});
  final TeacherClassInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(profileProvider).value?.userId;
    final mine = info.hostId == uid;
    final repo = ref.read(loungeRepositoryProvider);

    final statusColor = switch (info.status) {
      'recruiting' => const Color(0xFF0E9F6E),
      'confirmed' => AppColors.teacherNavy,
      'done' => AppColors.textTertiary,
      _ => AppColors.textTertiary,
    };

    final detail = [
      if (info.durationMinutes != null) '${info.durationMinutes}분',
      if (info.scheduledAt != null)
        DateFormat('M/d(E) HH:mm', 'ko').format(info.scheduledAt!),
      if ((info.location ?? '').isNotEmpty) info.location!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(info.statusLabel,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(info.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text('${info.costPoints}P',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${info.hostName ?? "선생님"} 선생님 · 신청 ${info.enrolledCount}명 / 최소 ${info.minParticipants}명${info.maxParticipants != null ? " (최대 ${info.maxParticipants})" : ""}',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (detail.isNotEmpty)
              Text(detail,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12, color: AppColors.textSecondary)),
            if ((info.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(info.description!,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, color: AppColors.textPrimary)),
            ],
            if (mine && info.enrolledNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('신청: ${info.enrolledNames.join(", ")}',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5, color: AppColors.textTertiary)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                if (mine && info.status == 'recruiting')
                  OutlinedButton(
                    onPressed: () async {
                      final err = await repo.cancelClass(info.id);
                      invalidateLounge(ref);
                      if (context.mounted && err != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(err)));
                      }
                    },
                    child: Text('클래스 취소',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  )
                else if (!mine &&
                    info.status == 'recruiting' &&
                    !info.myEnrolled)
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    onPressed: () async {
                      final err = await repo.enrollClass(info.id);
                      invalidateLounge(ref);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(err ?? '신청 완료! 🎓')));
                      }
                    },
                    child: Text('신청하기 (${info.costPoints}P)',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  )
                else if (!mine &&
                    info.status == 'recruiting' &&
                    info.myEnrolled)
                  OutlinedButton(
                    onPressed: () async {
                      final err = await repo.cancelEnrollment(info.id);
                      invalidateLounge(ref);
                      if (context.mounted && err != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(err)));
                      }
                    },
                    child: Text('신청 취소',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  )
                else if (info.myEnrolled && info.status == 'confirmed')
                  Text('참여 확정! 🎉',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.teacherNavy)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════ 내역 탭 ═══════════
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(myTeacherTxProvider);
    final exAsync = ref.watch(myTeacherExchangesProvider);
    final pendingAsync = isAdmin
        ? ref.watch(pendingTeacherExchangesProvider)
        : const AsyncValue<List<TeacherExchange>>.data([]);
    final repo = ref.read(loungeRepositoryProvider);

    return RefreshIndicator(
      onRefresh: () async => invalidateLounge(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (isAdmin) ...[
            const SectionHeader(title: '🛎️ 승인 대기 (리더십팀)'),
            ...(pendingAsync.value ?? []).map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: PbsCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${e.teacherName ?? "선생님"} · ${e.itemName}',
                                  style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                              Text(
                                  '${e.costPoints}P · ${DateFormat('M/d HH:mm').format(e.requestedAt)}',
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 11.5,
                                      color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final err = await repo.cancelExchange(e.id);
                            invalidateLounge(ref);
                            if (context.mounted && err != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)));
                            }
                          },
                          child: Text('반려',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12.5,
                                  color: AppColors.textTertiary)),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.teacherNavy),
                          onPressed: () async {
                            await repo.fulfillExchange(e.id);
                            invalidateLounge(ref);
                          },
                          child: Text('지급 완료',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                )),
            if ((pendingAsync.value ?? []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('대기 중인 교환 신청이 없어요.',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12.5, color: AppColors.textTertiary)),
              ),
            const SizedBox(height: 10),
          ],
          const SectionHeader(title: '🎁 내 교환 신청'),
          ...(exAsync.value ?? []).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: PbsCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.itemName,
                            style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                      Text('${e.costPoints}P',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teacherNavy)),
                      const SizedBox(width: 10),
                      Text(e.statusLabel,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: e.status == 'fulfilled'
                                  ? AppColors.primary
                                  : AppColors.textTertiary)),
                    ],
                  ),
                ),
              )),
          if ((exAsync.value ?? []).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('아직 교환 신청이 없어요.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, color: AppColors.textTertiary)),
            ),
          const SizedBox(height: 10),
          const SectionHeader(title: '🌱 포인트 내역'),
          ...(txAsync.value ?? []).map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(t.sourceLabel,
                          style: GoogleFonts.notoSansKr(fontSize: 13.5)),
                    ),
                    Text(
                      '${t.points > 0 ? "+" : ""}${t.points}P',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: t.points > 0
                              ? AppColors.primary
                              : const Color(0xFFDC2626)),
                    ),
                    const SizedBox(width: 10),
                    Text(DateFormat('M/d').format(t.createdAt),
                        style: GoogleFonts.notoSansKr(
                            fontSize: 11.5, color: AppColors.textTertiary)),
                  ],
                ),
              )),
          if ((txAsync.value ?? []).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  '아직 포인트 내역이 없어요.\n칭찬·K-ODR·CICO 활동이 자동으로 쌓여요!',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                      height: 1.5)),
            ),
        ],
      ),
    );
  }
}
