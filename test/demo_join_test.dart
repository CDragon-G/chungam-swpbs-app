import 'package:flutter_test/flutter_test.dart';
import 'package:pbs_plus/core/utils/error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('익명 로그인을 켜지 않았으면 강사에게 알리라고 안내한다 (079)', () {
    const msg = '체험 입장이 아직 열리지 않았어요. 강사님께 알려 주세요.';
    expect(
      translateError(const AuthException('Anonymous sign-ins are disabled',
          code: 'anonymous_provider_disabled')),
      msg,
    );
    expect(
      translateError(const AuthException('Anonymous sign-ins are disabled')),
      msg,
    );
  });

  test('체험 입장 서버 오류 문구는 그대로 보여 준다', () {
    expect(
        translateError(StateError('체험 코드를 다시 확인해 주세요')), '체험 코드를 다시 확인해 주세요');
  });
}
