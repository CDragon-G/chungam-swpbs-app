import '../../honor/weekly_honor_marquee.dart';
import '../../notifications/models/app_notification.dart';
import '../models/growth_status.dart';

/// 🌱 식물 말풍선 문장.
///
/// [news] 는 지금 알려줄 소식(새 강화물, 받은 칭찬 편지, 오늘 점검 등)이라
/// 말풍선이 먼저, 그리고 가끔 다시 말한다. 나머지는 평소에 돌아가며 하는 말이다.
/// 시간대와 요일에 따라 섞이는 말이 달라진다.
///
/// 한 줄은 16자 안팎으로, 줄바꿈은 \n 으로 직접 넣는다 (자동 줄바꿈에 맡기지 않는다).
class PlantLines {
  PlantLines._();

  // ── 학생 ─────────────────────────────────────────────────

  static List<String> student(DateTime now) => [
        ..._studentAlways,
        ...switch (_part(now)) {
          _Part.morning => _studentMorning,
          _Part.afternoon => _studentAfternoon,
          _Part.evening => _studentEvening,
          _Part.night => _studentNight,
        },
        ...switch (now.weekday) {
          DateTime.monday => const ['월요일이다!\n이번 주도 같이 자라자 💪'],
          DateTime.friday => const ['금요일이다!\n이번 주 정말 잘했어 🎉'],
          DateTime.saturday || DateTime.sunday => const [
              '주말엔 푹 쉬어!\n나도 쉬엄쉬엄 자랄게 🛌'
            ],
          _ => const <String>[],
        },
      ];

  /// 학생에게 지금 알려줄 소식.
  static List<String> studentNews({
    required List<AppNotification> notifications,
    required DateTime now,
    bool todayDone = false,
    bool checkinOpen = false,
    bool beforeOpen = false,
    String? opensText,
    GrowthStatus? growth,
    MyWeeklyHonor? honor,
    bool updateAvailable = false,
  }) {
    final out = <String>[];
    for (final n in _recentUnread(notifications, now)) {
      final line = switch (n.type) {
        'store_item' => '새 강화물이 들어왔어! 🎁\n${_short(n.body ?? '교환소에서 확인해봐')}',
        'praise' => '선생님께 칭찬받았구나! 💚\n덕분에 나도 쑥 컸어',
        'praise_mail' => '칭찬 우체통에 편지가 왔어! 💌\n얼른 열어봐',
        'rule' => '우리 학교 규칙 소식이 있어 📖\n알림에서 확인해봐',
        'growth' => null,
        _ => '새 소식이 있어 📢\n위의 종을 눌러봐',
      };
      if (line != null && !out.contains(line)) out.add(line);
    }

    if (!todayDone && checkinOpen) {
      out.add('오늘 자기점검 아직이지?\n나 목말라… 💧');
    } else if (!todayDone && beforeOpen && opensText != null) {
      out.add('자기점검은 $opensText부터!\n조금만 기다려 ⏰');
    }

    if (honor != null && honor.joined) {
      if (honor.isTop) {
        out.add('지금 우리 반\n명예 식집사는 너야! 👑');
      } else if (honor.gap > 0 && honor.gap <= 30) {
        out.add('우리 반 명예 식집사까지\n${honor.gap}점 남았어! 👑');
      }
    }

    final g = growth;
    if (g != null &&
        !g.isMaxLevel &&
        !g.isGateLocked &&
        !g.isDayLocked &&
        g.pointsToNext > 0 &&
        g.pointsToNext <= 10) {
      out.add('Lv.${g.level + 1}까지\n양분 ${g.pointsToNext}만 더! 🌱');
    }

    if (updateAvailable) {
      out.add('새 버전이 나왔어! 📲\n스토어에서 업데이트해줘');
    }
    return out;
  }

  // ── 선생님 ───────────────────────────────────────────────

  static List<String> teacher(DateTime now) => [
        ..._teacherAlways,
        ...switch (_part(now)) {
          _Part.morning => const [
              '좋은 아침이에요!\n오늘도 힘내세요 ☀️',
              '아침 인사 한 번이\n아이의 하루를 바꿔요 🌅',
            ],
          _Part.afternoon => const [
              '오후 1시부터 아이들이\n점검하러 와요 📝',
              '오후도 힘내세요!\n저도 광합성 중이에요 🌞',
            ],
          _Part.evening || _Part.night => const [
              '오늘도 수고 많으셨어요.\n푹 쉬세요 🌙',
              '퇴근하셨나요?\n오늘 기록은 제가 지킬게요 🌿',
            ],
        },
        ...switch (now.weekday) {
          DateTime.monday => const ['한 주의 시작이에요.\n이번 주도 함께해요 💪'],
          DateTime.friday => const ['한 주 동안 정말\n고생 많으셨어요 🎉'],
          _ => const <String>[],
        },
      ];

  /// 선생님에게 지금 알려줄 소식.
  static List<String> teacherNews({
    required List<AppNotification> notifications,
    required DateTime now,
    int praiseMailToday = 0,
    int? participants,
    double? participationPct,
    bool updateAvailable = false,
  }) {
    final out = <String>[];
    for (final n in _recentUnread(notifications, now)) {
      final line = switch (n.type) {
        'support_referral' => '학맞통 안건이 올라왔어요 🧩\n알림을 확인해주세요',
        'cico_recommend' => 'CICO를 권장할 학생이 있어요 🔔\n알림을 확인해주세요',
        'exchange' => '강화물 교환 요청이 왔어요 🛍️\n교환소에서 처리해주세요',
        'praise_mail_report' => '칭찬 편지 신고가 있어요 💌\n확인 부탁드려요',
        'store_item' => '교환소에 새 강화물이\n등록됐어요 🎁',
        'rule' => '우리 학교 규칙이\n바뀌었어요 📖',
        'praise_sent' || 'growth' => null,
        _ => '새 알림이 있어요 🔔\n위의 종을 눌러주세요',
      };
      if (line != null && !out.contains(line)) out.add(line);
    }

    if (praiseMailToday > 0) {
      out.add('오늘 아이들이 칭찬 편지를\n$praiseMailToday통 주고받았어요 💌');
    }
    if (participants != null &&
        participationPct != null &&
        participants > 0 &&
        now.hour >= 13) {
      out.add(
          '오늘 $participants명이 점검했어요.\n참여율 ${participationPct.round()}%예요 📊');
    }
    if (updateAvailable) {
      out.add('새 버전이 나왔어요 📲\n스토어에서 업데이트해주세요');
    }
    return out;
  }

  // ── 공통 ─────────────────────────────────────────────────

  /// 최근 3일 안에 온, 아직 안 읽은 알림 (최신 순, 최대 3개).
  static Iterable<AppNotification> _recentUnread(
      List<AppNotification> all, DateTime now) {
    return all
        .where((n) =>
            !n.isRead && now.difference(n.createdAt) < const Duration(days: 3))
        .take(3);
  }

  static String _short(String s) {
    final t = s.trim();
    return t.length <= 16 ? t : '${t.substring(0, 15)}…';
  }

  static _Part _part(DateTime now) {
    final h = now.hour;
    if (h >= 6 && h < 12) return _Part.morning;
    if (h >= 12 && h < 17) return _Part.afternoon;
    if (h >= 17 && h < 21) return _Part.evening;
    return _Part.night;
  }

  static const _studentAlways = [
    '오늘도 와줘서 고마워!\n네 덕분에 쑥쑥 크고 있어 🌱',
    '규칙을 지키는 너, 진짜 멋져!',
    '칭찬받으면 나한테도 양분이 와!\n완전 꿀맛이야 💚',
    '내일도 물 주러 와줘~ 기다릴게!',
    '우리 반이 수업맛집 되면\n나 꽃 피울지도 몰라 🌸',
    '조금씩 자라는 게\n제일 튼튼하게 크는 거래 🌿',
    '친구한테 칭찬 편지 써봤어?\n칭찬 우체통이 기다려 💌',
    '어제보다 딱 한 걸음!\n그거면 충분해 👣',
    '실수해도 괜찮아.\n다시 하면 되니까 🙂',
    '네가 웃으면\n내 잎도 반짝여 ✨',
    '포인트 모아서\n교환소 구경 가볼까? 🛒',
    '인사 한 번이\n교실을 따뜻하게 해 👋',
    '복도에서는 천천히!\n나도 천천히 자라는 중 🐢',
    '정리 정돈 잘하면\n내 화분도 깨끗해져 🧹',
    '친구 말을 끝까지 들어주기,\n그게 진짜 멋이야 👂',
    '오늘 고마웠던 사람\n한 명만 떠올려볼래? 💭',
    '매일의 약속이\n내 뿌리를 튼튼하게 해 🌳',
    '도움을 청하는 것도\n용기야 💪',
    '모두가 함께 키우는 나무라서\n더 특별해 🌍',
    '이번 주 명예 식집사는\n누가 될까? 👑',
    '물은 매일 조금씩!\n점검도 매일 조금씩 💧',
    '네가 지킨 규칙 하나가\n우리 반을 바꿔 🔑',
  ];

  static const _studentMorning = [
    '좋은 아침!\n오늘 하루도 잘 부탁해 ☀️',
    '아침밥은 먹었어?\n나는 햇빛 먹는 중 🌞',
    '1교시 화이팅!\n나도 광합성 화이팅 🌿',
  ];

  static const _studentAfternoon = [
    '오늘 하루 어땠어?\n점검하면서 돌아보자 📝',
    '오후엔 나도 조금 졸려…\n그래도 힘내자 😪',
    '하교 후 점검 한 번이면\n나 쑥 자라 🌱',
  ];

  static const _studentEvening = [
    '저녁은 먹었어?\n오늘도 수고 많았어 🌙',
    '오늘 점검 잊지 않았지?\n자기 전에 한 번! 💧',
  ];

  static const _studentNight = [
    '늦었다! 푹 자야\n내일 쑥쑥 자라지 😴',
    '별 보면서 쉬는 중…\n너도 푹 쉬어 ⭐',
  ];

  static const _teacherAlways = [
    '선생님의 칭찬 한 마디가\n저에겐 최고의 양분이에요 💚',
    '오늘도 아이들 곁을\n지켜주셔서 고마워요 🌱',
    '꾸준한 기록이 학교를 바꿔요.\n선생님, 최고예요!',
    '수업맛집 투표,\n아이들이 은근히 기다려요 🍽️',
    '참여율이 오르면\n제 잎이 반짝반짝해져요 ✨',
    '천천히 자라도 괜찮아요.\n우리 같이 자라는 중이에요 🌿',
    '칭찬은 구체적일수록\n오래 기억된대요 💬',
    'K-ODR 한 줄이\n한 아이를 지켜요 📋',
    '칭찬 네 번에 교정 한 번,\n4:1이 좋대요 ⚖️',
    'Tier 1이 튼튼하면\nTier 3이 줄어들어요 🔺',
    '교환소에 새 강화물을\n올려보는 건 어때요? 🎁',
    '선생님도 잠깐 쉬어가세요.\n따뜻한 차 한 잔 어때요? 🍵',
    '오늘 한 아이의 이름을\n불러주셨나요? 🙂',
    '규칙은 가르치는 거래요.\n한 번 더 보여주기 👀',
    '작은 변화도\n충분히 칭찬할 만해요 👏',
  ];
}

enum _Part { morning, afternoon, evening, night }
