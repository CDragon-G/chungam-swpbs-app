import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/features/points/models/point_store_item.dart';

GroupItemStatus _st(Map<String, dynamic> extra) => GroupItemStatus.fromMap({
      'goal': 3000,
      'raised': 0,
      'people': 0,
      'my_amount': 0,
      'achieved': false,
      'closed': false,
      'top': const [],
      ...extra,
    });

void main() {
  test('player_slots 가 없으면 지금의 함께 키우기 (077 전 서버도 같다)', () {
    final it = PointStoreItem.fromMap({
      'id': 'i1',
      'school_id': 's1',
      'name': '과자 파티',
      'cost_points': 5000,
      'item_type': 'group',
      'created_at': '2026-11-04T00:00:00Z',
    });
    expect(it.isSports, isFalse);
    final st = _st({});
    expect(st.isSports, isFalse);
    expect(st.myMaxAddable(1000), 1000);
  });

  test('개별 강화물에 player_slots 가 있어도 스포츠 경기가 아니다', () {
    final it = PointStoreItem.fromMap({
      'id': 'i1',
      'school_id': 's1',
      'name': '어묵',
      'cost_points': 200,
      'player_slots': 10,
      'created_at': '2026-11-04T00:00:00Z',
    });
    expect(it.isSports, isFalse);
  });

  test('응원은 남은 응원 몫까지만 보탤 수 있다', () {
    final st = _st({
      'player_slots': 12,
      'raised': 1500,
      'supporter_raised': 700,
      'supporter_cap': 900,
      'players': 4,
      'supporters': 6,
    });
    expect(st.isSports, isTrue);
    expect(st.supporterLeft, 200);
    expect(st.myMaxAddable(1000, role: 'supporter'), 200);
    expect(st.myMaxAddable(1000, role: 'player'), 1000);
    expect(st.playerRaised, 800);
    expect(st.canJoinAsPlayer, isTrue);
  });

  test('선수 자리가 다 차면 선수로 들어올 수 없다', () {
    final st = _st({
      'player_slots': 8,
      'players': 8,
      'supporter_cap': 900,
    });
    expect(st.playersFull, isTrue);
    expect(st.canJoinAsPlayer, isFalse);
  });

  test('이미 선수면 응원 몫 상한을 받지 않는다', () {
    final st = _st({
      'player_slots': 8,
      'players': 8,
      'supporter_raised': 900,
      'supporter_cap': 900,
      'my_role': 'player',
      'my_amount': 100,
      'max_per_student': 600,
    });
    expect(st.isPlayer, isTrue);
    expect(st.supporterLeft, 0);
    // 1인 최대 600P - 이미 낸 100P
    expect(st.myMaxAddable(1000, role: 'player'), 500);
    expect(st.myMaxAddable(1000), 500);
  });

  test('막대: 선수 몫과 응원 몫이 합쳐 100% 를 넘지 않는다', () {
    final st = _st({
      'player_slots': 10,
      'raised': 3000,
      'supporter_raised': 900,
      'supporter_cap': 900,
    });
    expect(st.playerProgress, closeTo(0.7, 1e-9));
    expect(st.supporterProgress, closeTo(0.3, 1e-9));
    expect(st.playerProgress + st.supporterProgress, lessThanOrEqualTo(1.0));
  });
}
