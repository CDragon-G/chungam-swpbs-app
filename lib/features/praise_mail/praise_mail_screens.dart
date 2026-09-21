import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/providers/profile_provider.dart';
import '../../shared/widgets/pbs_card.dart';
import '../calendar/providers/calendar_provider.dart';
import '../homeroom/providers/homeroom_provider.dart';

// ══════════════════ 모델 ══════════════════

class PraiseTemplate {
  const PraiseTemplate({
    required this.id,
    required this.category,
    required this.emoji,
    required this.sentence,
  });
  final String id;
  final String category;
  final String emoji;
  final String sentence;

  factory PraiseTemplate.fromMap(Map<String, dynamic> m) => PraiseTemplate(
        id: m['id'] as String,
        category: (m['category'] as String?) ?? '',
        emoji: (m['emoji'] as String?) ?? '💌',
        sentence: (m['sentence'] as String?) ?? '',
      );
}

class Classmate {
  const Classmate({
    required this.userId,
    required this.name,
    required this.studentNum,
    required this.sent,
  });
  final String userId;
  final String name;
  final int? studentNum;

  /// 이번 주에 이미 이 친구에게 보냈는가
  final bool sent;

  factory Classmate.fromMap(Map<String, dynamic> m) => Classmate(
        userId: m['user_id'] as String,
        name: (m['name'] as String?) ?? '',
        studentNum: (m['student_num'] as num?)?.toInt(),
        sent: m['sent'] == true,
      );
}

class PraiseMailHome {
  const PraiseMailHome({
    required this.remaining,
    required this.used,
    required this.templates,
    required this.friends,
  });
  final int remaining;
  final int used;
  final List<PraiseTemplate> templates;
  final List<Classmate> friends;

  factory PraiseMailHome.fromMap(Map<String, dynamic> m) => PraiseMailHome(
        remaining: (m['remaining'] as num?)?.toInt() ?? 0,
        used: (m['used'] as num?)?.toInt() ?? 0,
        templates: ((m['templates'] as List?) ?? const [])
            .map((e) =>
                PraiseTemplate.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        friends: ((m['friends'] as List?) ?? const [])
            .map((e) => Classmate.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class ReceivedMail {
  const ReceivedMail({
    required this.id,
    required this.emoji,
    required this.category,
    required this.sentence,
    required this.senderName,
    required this.createdAt,
    required this.isRead,
  });
  final String id;
  final String emoji;
  final String category;
  final String sentence;

  /// 익명이면 null — 서버가 이름을 아예 싣지 않는다.
  final String? senderName;
  final DateTime createdAt;
  final bool isRead;

  factory ReceivedMail.fromMap(Map<String, dynamic> m) => ReceivedMail(
        id: m['id'] as String,
        emoji: (m['emoji'] as String?) ?? '💌',
        category: (m['category'] as String?) ?? '',
        sentence: (m['sentence'] as String?) ?? '',
        senderName: m['sender_name'] as String?,
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        isRead: m['is_read'] == true,
      );
}

class SentMail {
  const SentMail({
    required this.name,
    required this.emoji,
    required this.sentence,
    required this.isAnonymous,
  });
  final String name;
  final String emoji;
  final String sentence;
  final bool isAnonymous;

  factory SentMail.fromMap(Map<String, dynamic> m) => SentMail(
        name: (m['name'] as String?) ?? '',
        emoji: (m['emoji'] as String?) ?? '💌',
        sentence: (m['sentence'] as String?) ?? '',
        isAnonymous: m['is_anonymous'] == true,
      );
}

String _dateLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '오늘';
  if (diff == 1) return '어제';
  if (diff < 7) return '$diff일 전';
  return '${d.month}월 ${d.day}일';
}

// ══════════════════ 데이터 ══════════════════

Map<String, dynamic> _okOrThrow(dynamic res, String fallback) {
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) {
    throw StateError(m['error'] as String? ?? fallback);
  }
  return m;
}

final praiseMailHomeProvider =
    FutureProvider.autoDispose<PraiseMailHome>((ref) async {
  final res = await SupabaseService.client.rpc('praise_mail_home');
  return PraiseMailHome.fromMap(_okOrThrow(res, '칭찬 우체통을 열지 못했어요'));
});

final praiseMailboxProvider =
    FutureProvider.autoDispose<List<ReceivedMail>>((ref) async {
  final res = await SupabaseService.client
      .rpc('my_praise_mailbox', params: {'p_limit': 100});
  return ((res as List?) ?? const [])
      .map((e) => ReceivedMail.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

final sentPraiseMailProvider =
    FutureProvider.autoDispose<List<SentMail>>((ref) async {
  final res = await SupabaseService.client.rpc('my_sent_praise_mail');
  return ((res as List?) ?? const [])
      .map((e) => SentMail.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// 홈 메뉴 배지용 — 안 읽은 칭찬 편지 수.
final unreadPraiseMailProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final res = await SupabaseService.client.rpc('unread_praise_mail_count');
    return (res as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0; // 서버에 기능이 아직 없어도 홈 화면은 멀쩡해야 한다
  }
});

// ══════════════════ 학생 — 칭찬 우체통 ══════════════════

/// 💌 칭찬 우체통 — 같은 반 친구의 좋은 행동을 칭찬한다.
///
/// 학생이 직접 쓰는 글자는 없다. 친구 · 문장 · 이름 공개 여부만 고른다.
/// 문장도 앱이 아니라 서버 목록에서 꺼내 쓰기 때문에, 앱을 조작해도
/// 목록에 없는 말은 들어갈 수 없다.
class PraiseMailScreen extends ConsumerStatefulWidget {
  const PraiseMailScreen({super.key});

  @override
  ConsumerState<PraiseMailScreen> createState() => _PraiseMailScreenState();
}

class _PraiseMailScreenState extends ConsumerState<PraiseMailScreen> {
  @override
  void initState() {
    super.initState();
    // 편지함을 열면 읽음 처리
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await SupabaseService.client.rpc('mark_praise_mail_read');
        if (mounted) ref.invalidate(unreadPraiseMailProvider);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('💌 칭찬 우체통',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          bottom: TabBar(
            labelColor: AppColors.studentGreen,
            indicatorColor: AppColors.studentGreen,
            labelStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
            tabs: const [Tab(text: '받은 편지'), Tab(text: '칭찬 보내기')],
          ),
        ),
        body: const TabBarView(
          children: [_Inbox(), _Compose()],
        ),
      ),
    );
  }
}

// ── 받은 편지 ──────────────────────────────────

class _Inbox extends ConsumerWidget {
  const _Inbox();

  Future<void> _hide(
      BuildContext context, WidgetRef ref, ReceivedMail m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('이 편지를 숨길까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '사실과 다른 칭찬이면 숨길 수 있어요.\n'
          '담임 선생님께 확인 요청이 함께 전달돼요.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('숨기기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await SupabaseService.client
          .rpc('hide_praise_mail', params: {'p_id': m.id});
      _okOrThrow(res, '숨기지 못했어요');
      ref.invalidate(praiseMailboxProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('숨겼어요. 담임 선생님께 알렸어요.')));
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
    final async = ref.watch(praiseMailboxProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(praiseMailboxProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(translateError(e),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
          ),
        ]),
        data: (items) {
          if (items.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              const Center(child: Text('📭', style: TextStyle(fontSize: 48))),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '아직 받은 편지가 없어요.\n'
                  '먼저 친구를 칭찬해 보는 건 어때요?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      height: 1.7,
                      color: AppColors.textSecondary),
                ),
              ),
            ]);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: PbsCard(
                  color: m.isRead ? null : const Color(0xFFFFF7ED),
                  border: Border.all(
                      color: m.isRead
                          ? AppColors.borderLight
                          : const Color(0xFFFED7AA)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                m.sentence,
                                maxLines: 1,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.senderName == null
                                  ? '익명의 친구가 보냈어요 · ${_dateLabel(m.createdAt)}'
                                  : '${m.senderName} 친구가 보냈어요 · ${_dateLabel(m.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 18, color: AppColors.textTertiary),
                        onSelected: (_) => _hide(context, ref, m),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'hide',
                            child: Text('사실이 아니에요',
                                style: GoogleFonts.notoSansKr(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── 칭찬 보내기 ────────────────────────────────

class _Compose extends ConsumerStatefulWidget {
  const _Compose();

  @override
  ConsumerState<_Compose> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<_Compose> {
  Classmate? _friend;
  PraiseTemplate? _template;
  bool _anonymous = true;
  bool _sending = false;

  Future<void> _send(String myName) async {
    final friend = _friend;
    final template = _template;
    if (friend == null || template == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${friend.name}에게 보낼까요?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '${template.emoji} ${template.sentence}\n\n'
          '${_anonymous ? '익명으로 보내요' : '내 이름($myName)을 밝혀요'} · 보낸 뒤에는 취소할 수 없어요',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('다시 고를게요', style: GoogleFonts.notoSansKr()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.studentGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('보내기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      final res = await SupabaseService.client.rpc('send_praise_mail', params: {
        'p_recipient': friend.userId,
        'p_template': template.id,
        'p_anonymous': _anonymous,
      });
      _okOrThrow(res, '보내지 못했어요');
      ref.invalidate(praiseMailHomeProvider);
      ref.invalidate(sentPraiseMailProvider);
      setState(() {
        _friend = null;
        _template = null;
        _anonymous = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('💌 ${friend.name}에게 칭찬을 보냈어요!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(praiseMailHomeProvider);
    final myName = ref.watch(profileProvider).value?.nickname ?? '나';

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Text(translateError(e),
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
        ),
      ),
      data: (home) {
        // 칭찬 우체통도 자기점검과 같은 시간에 연다 (수업일 · 하교 후).
        // 서버도 같은 기준으로 막지만, 고르고 나서 거절당하지 않도록 먼저 안내한다.
        final today = ref.watch(todaySchoolStatusProvider).value;
        if (today != null && !today.isSchoolDay) {
          return const _ClosedNotice(
            emoji: '🌙',
            title: '오늘은 쉬는 날이에요',
            body: '칭찬 우체통은 수업일에 열려요.\n다음 수업일에 친구를 칭찬해봐요!',
          );
        }
        if (today != null && today.isBeforeOpen) {
          return _ClosedNotice(
            emoji: '🕐',
            title: '${today.opensText}부터 열려요',
            body: '자기점검과 같은 시간에 열어요.\n수업 끝나고 다시 와줘!',
          );
        }

        final noneLeft = home.remaining <= 0;
        final canSend =
            !noneLeft && _friend != null && _template != null && !_sending;

        // 문장을 분류별로 묶는다 (서버가 준 순서 유지)
        final groups = <String, List<PraiseTemplate>>{};
        for (final t in home.templates) {
          groups.putIfAbsent(t.category, () => []).add(t);
        }

        return ListView(
          padding: const EdgeInsets.all(AppSizes.lg),
          children: [
            // 이번 주 남은 횟수
            PbsCard(
              color:
                  noneLeft ? const Color(0xFFF1F5F9) : const Color(0xFFF0FDF4),
              child: Row(
                children: [
                  Text(noneLeft ? '📪' : '📮',
                      style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          noneLeft
                              ? '이번 주 칭찬을 모두 보냈어요'
                              : '이번 주 ${home.remaining}번 더 보낼 수 있어요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          noneLeft
                              ? '월요일에 다시 3번 보낼 수 있어요'
                              : '일주일에 3번, 서로 다른 친구에게',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _SentThisWeek(),

            if (!noneLeft) ...[
              const _Step(n: 1, title: '누구를 칭찬할까요?'),
              if (home.friends.isEmpty)
                Text('같은 반 친구가 아직 가입하지 않았어요',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12.5, color: AppColors.textSecondary))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in home.friends)
                      ChoiceChip(
                        label: Text(
                          f.sent ? '${f.name} ✓' : f.name,
                          maxLines: 1,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: _friend?.userId == f.userId
                                  ? FontWeight.w900
                                  : FontWeight.w600),
                        ),
                        selected: _friend?.userId == f.userId,
                        selectedColor: const Color(0xFFBBF7D0),
                        // 이번 주에 이미 보낸 친구는 고를 수 없다
                        onSelected:
                            f.sent ? null : (_) => setState(() => _friend = f),
                      ),
                  ],
                ),
              const _Step(n: 2, title: '어떤 모습을 칭찬할까요?'),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    '${entry.value.first.emoji} ${entry.key}',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary),
                  ),
                ),
                for (final t in entry.value)
                  _SentenceTile(
                    template: t,
                    selected: _template?.id == t.id,
                    onTap: () => setState(() => _template = t),
                  ),
              ],
              const _Step(n: 3, title: '내 이름을 밝힐까요?'),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('익명으로',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w700)),
                    icon: const Icon(Icons.visibility_off_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('이름 밝히기',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w700)),
                    icon: const Icon(Icons.badge_rounded, size: 16),
                  ),
                ],
                selected: {_anonymous},
                onSelectionChanged: (s) => setState(() => _anonymous = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _anonymous ? '친구에게는 누가 보냈는지 보이지 않아요' : '친구에게 내 이름이 함께 전해져요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSizes.lg),
              if (_friend != null && _template != null)
                _Preview(
                  friend: _friend!.name,
                  template: _template!,
                  from: _anonymous ? '익명의 친구' : myName,
                ),
              const SizedBox(height: AppSizes.md),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.studentGreen,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: canSend ? () => _send(myName) : null,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _friend == null
                            ? '칭찬할 친구를 골라주세요'
                            : _template == null
                                ? '칭찬할 모습을 골라주세요'
                                : '💌 칭찬 보내기',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                '선생님은 익명 편지도 누가 보냈는지 확인할 수 있어요.',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
            const SizedBox(height: AppSizes.xxxl),
          ],
        );
      },
    );
  }
}

/// 아직 열리지 않았을 때 보여주는 안내.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.xl),
      children: [
        const SizedBox(height: 40),
        Text(emoji,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
                fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
                fontSize: 13, height: 1.7, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title});
  final int n;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.lg, bottom: AppSizes.sm),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.studentGreen, shape: BoxShape.circle),
            child: Text('$n',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });
  final PraiseTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFFDCFCE7) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color:
                      selected ? AppColors.studentGreen : AppColors.borderLight,
                  width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected
                      ? AppColors.studentGreen
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      template.sentence,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.friend,
    required this.template,
    required this.from,
  });
  final String friend;
  final PraiseTemplate template;
  final String from;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💌 $friend에게 도착할 편지',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB45309))),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${template.emoji} ${template.sentence}',
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Text('$from 보냈어요',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 이번 주에 보낸 칭찬 — 누구에게 보냈는지 스스로 확인한다.
class _SentThisWeek extends ConsumerWidget {
  const _SentThisWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = ref.watch(sentPraiseMailProvider).value ?? const [];
    if (sent.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이번 주에 보낸 칭찬',
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final s in sent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text('${s.emoji} ${s.sentence}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 6),
                    Text(s.isAnonymous ? '익명' : '이름',
                        maxLines: 1,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ 선생님 — 학급 칭찬 우체통 ══════════════════

class ClassMail {
  const ClassMail({
    required this.id,
    required this.senderName,
    required this.senderNum,
    required this.recipientName,
    required this.recipientNum,
    required this.emoji,
    required this.sentence,
    required this.isAnonymous,
    required this.hidden,
    required this.hiddenReason,
    required this.createdAt,
  });
  final String id;
  final String senderName;
  final int? senderNum;
  final String recipientName;
  final int? recipientNum;
  final String emoji;
  final String sentence;
  final bool isAnonymous;
  final bool hidden;
  final String? hiddenReason; // not_true | teacher
  final DateTime createdAt;

  factory ClassMail.fromMap(Map<String, dynamic> m) => ClassMail(
        id: m['id'] as String,
        senderName: (m['sender_name'] as String?) ?? '',
        senderNum: (m['sender_num'] as num?)?.toInt(),
        recipientName: (m['recipient_name'] as String?) ?? '',
        recipientNum: (m['recipient_num'] as num?)?.toInt(),
        emoji: (m['emoji'] as String?) ?? '💌',
        sentence: (m['sentence'] as String?) ?? '',
        isAnonymous: m['is_anonymous'] == true,
        hidden: m['hidden'] == true,
        hiddenReason: m['hidden_reason'] as String?,
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

typedef _ClassKey = ({int grade, int classNum});

final classPraiseMailProvider = FutureProvider.autoDispose
    .family<List<ClassMail>, _ClassKey>((ref, key) async {
  final res = await SupabaseService.client.rpc('class_praise_mail', params: {
    'p_grade': key.grade,
    'p_class': key.classNum,
    'p_days': 60,
  });
  final m = _okOrThrow(res, '불러오지 못했어요');
  return ((m['items'] as List?) ?? const [])
      .map((e) => ClassMail.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// 칭찬 우체통 통계 — 선생님용. 숫자만 있고 이름은 없다.
/// 숨김 처리된 편지는 세지 않는다.
class PraiseMailStats {
  const PraiseMailStats({
    this.today = 0,
    this.todaySenders = 0,
    this.week = 0,
    this.myClassToday,
    this.myClassLabel,
  });

  final int today;
  final int todaySenders;
  final int week;
  final int? myClassToday;
  final String? myClassLabel;

  factory PraiseMailStats.fromMap(Map<String, dynamic> m) => PraiseMailStats(
        today: (m['today'] as num?)?.toInt() ?? 0,
        todaySenders: (m['today_senders'] as num?)?.toInt() ?? 0,
        week: (m['week'] as num?)?.toInt() ?? 0,
        myClassToday: (m['my_class_today'] as num?)?.toInt(),
        myClassLabel: m['my_class_label'] as String?,
      );
}

final praiseMailStatsProvider =
    FutureProvider.autoDispose<PraiseMailStats?>((ref) async {
  final res = await SupabaseService.client.rpc('praise_mail_stats');
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) return null;
  return PraiseMailStats.fromMap(m);
});

/// 오늘 학생들 사이에 오간 칭찬 편지 수.
class PraiseMailStatsCard extends ConsumerWidget {
  const PraiseMailStatsCard({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(praiseMailStatsProvider).value;
    if (s == null) return const SizedBox.shrink();
    Widget cell(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFDB2777))),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        );
    return GestureDetector(
      onTap: onTap,
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('💌 칭찬 우체통 · 오늘',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13.5, fontWeight: FontWeight.w900)),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                cell('주고받은 편지', '${s.today}통'),
                cell('보낸 학생', '${s.todaySenders}명'),
                cell('이번 주', '${s.week}통'),
              ],
            ),
            if (s.myClassToday != null && s.myClassLabel != null) ...[
              const SizedBox(height: 10),
              Text(
                '${s.myClassLabel} 학생이 오늘 받은 편지 ${s.myClassToday}통',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 💌 학급 칭찬 우체통 — 담임·관리자용.
///
/// 익명 편지도 보낸 학생 실명을 보여준다. 학생에게 익명이라는 약속은
/// '친구에게' 익명이라는 뜻이고, 장난을 막으려면 선생님은 알아야 한다.
class TeacherPraiseMailScreen extends ConsumerStatefulWidget {
  const TeacherPraiseMailScreen({super.key});

  @override
  ConsumerState<TeacherPraiseMailScreen> createState() =>
      _TeacherPraiseMailScreenState();
}

class _TeacherPraiseMailScreenState
    extends ConsumerState<TeacherPraiseMailScreen> {
  _ClassKey? _picked;

  Future<void> _hide(ClassMail m, _ClassKey key) async {
    try {
      final res = await SupabaseService.client
          .rpc('teacher_hide_praise_mail', params: {'p_id': m.id});
      _okOrThrow(res, '숨기지 못했어요');
      ref.invalidate(classPraiseMailProvider(key));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminTeacher ?? false;
    final classes = ref.watch(schoolClassListProvider).value ?? const [];

    // 기본은 내 담임 학급
    final homeroom = (profile?.grade != null && profile?.classNum != null)
        ? (grade: profile!.grade!, classNum: profile.classNum!)
        : null;
    final key = _picked ?? homeroom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('💌 학급 칭찬 우체통',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          PbsCard(
            color: const Color(0xFFFFF7ED),
            child: Text(
              '학생들이 같은 반 친구에게 보낸 칭찬이에요.\n'
              '익명 편지도 선생님께는 보낸 학생 이름이 보여요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12.5, height: 1.6, color: const Color(0xFF92400E)),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const PraiseMailStatsCard(),
          const SizedBox(height: AppSizes.md),
          if (isAdmin && classes.isNotEmpty)
            DropdownButtonFormField<_ClassKey>(
              initialValue: key == null
                  ? null
                  : classes
                      .map((c) => (grade: c.grade, classNum: c.classNum))
                      .where((k) => k == key)
                      .firstOrNull,
              decoration: InputDecoration(
                labelText: '학급',
                filled: true,
                fillColor: AppColors.surface,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                for (final c in classes)
                  DropdownMenuItem(
                    value: (grade: c.grade, classNum: c.classNum),
                    child: Text(c.label, style: GoogleFonts.notoSansKr()),
                  ),
              ],
              onChanged: (k) => setState(() => _picked = k),
            ),
          if (key == null)
            Padding(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Text(
                isAdmin ? '학급을 골라주세요' : '담임 학급을 먼저 지정해 주세요 (담임반 관리)',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary),
              ),
            )
          else
            _ClassMailList(classKey: key, onHide: (m) => _hide(m, key)),
        ],
      ),
    );
  }
}

class _ClassMailList extends ConsumerWidget {
  const _ClassMailList({required this.classKey, required this.onHide});
  final _ClassKey classKey;
  final void Function(ClassMail) onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(classPraiseMailProvider(classKey));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSizes.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Text(translateError(e),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
      ),
      data: (items) {
        final reported =
            items.where((m) => m.hiddenReason == 'not_true').length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
              child: Text(
                '${classKey.grade}학년 ${classKey.classNum}반 · 최근 60일 ${items.length}통'
                '${reported > 0 ? ' · 확인 필요 $reported' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: reported > 0
                        ? AppColors.danger
                        : AppColors.textPrimary),
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Text('아직 오간 칭찬이 없어요',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style:
                        GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
              ),
            for (final m in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: PbsCard(
                  color: m.hiddenReason == 'not_true'
                      ? const Color(0xFFFEF2F2)
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${m.senderNum ?? '-'}번 ${m.senderName}  →  '
                              '${m.recipientNum ?? '-'}번 ${m.recipientName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 13, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (m.isAnonymous) const _Badge('익명'),
                          if (m.hidden)
                            _Badge(
                              m.hiddenReason == 'not_true' ? '학생이 숨김' : '숨김',
                              danger: m.hiddenReason == 'not_true',
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text('${m.emoji} ${m.sentence}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary)),
                          ),
                          Text(_dateLabel(m.createdAt),
                              maxLines: 1,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11, color: AppColors.textTertiary)),
                          if (!m.hidden)
                            IconButton(
                              tooltip: '숨기기',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.visibility_off_rounded,
                                  size: 18, color: AppColors.textTertiary),
                              onPressed: () => onHide(m),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFEE2E2) : AppColors.borderLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          maxLines: 1,
          style: GoogleFonts.notoSansKr(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: danger ? AppColors.danger : AppColors.textSecondary)),
    );
  }
}
