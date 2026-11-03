import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/features/points/models/point_store_item.dart';

PointStoreItem _item(Map<String, dynamic> extra) => PointStoreItem.fromMap({
      'id': 'i1',
      'school_id': 's1',
      'name': '따뜻한 어묵',
      'cost_points': 200,
      'created_at': '2026-11-02T00:00:00Z',
      ...extra,
    });

void main() {
  test('제한이 없으면 표시도 없다 (075 전 서버도 같다)', () {
    final it = _item({});
    expect(it.hasLimit, isFalse);
    expect(it.limitLabel, '');
  });

  test('기간별 표시', () {
    expect(_item({'limit_per_student': 1, 'limit_period': 'day'}).limitLabel,
        '하루 1번');
    expect(_item({'limit_per_student': 2, 'limit_period': 'week'}).limitLabel,
        '한 주 2번');
    expect(_item({'limit_per_student': 1, 'limit_period': 'month'}).limitLabel,
        '한 달 1번');
    expect(_item({'limit_per_student': 3, 'limit_period': 'total'}).limitLabel,
        '1인 3번');
  });
}
