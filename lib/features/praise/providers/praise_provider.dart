import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/praise_repository.dart';
import '../models/praise.dart';

final praiseRepositoryProvider =
    Provider<PraiseRepository>((_) => PraiseRepository());

/// 학생: 받은 칭찬 목록.
final myReceivedPraiseProvider = FutureProvider<List<Praise>>((ref) async {
  return ref.read(praiseRepositoryProvider).fetchMyReceived();
});

/// 학생: 안 읽은 칭찬 개수 (홈 배지용).
final unreadPraiseCountProvider = FutureProvider<int>((ref) async {
  return ref.read(praiseRepositoryProvider).unreadCount();
});
