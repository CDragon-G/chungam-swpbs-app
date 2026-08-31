import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/vote_repository.dart';
import '../models/vote_models.dart';

final voteRepositoryProvider = Provider<VoteRepository>((_) => VoteRepository());

final voteSubjectsProvider = FutureProvider<List<VoteSubject>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(voteRepositoryProvider).fetchSubjects(profile!.schoolId!);
});

final voteRoundsProvider = FutureProvider<List<VoteRound>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(voteRepositoryProvider).fetchRounds(profile!.schoolId!);
});

/// 현재 열린 라운드 (없으면 null).
final openRoundProvider = Provider<VoteRound?>((ref) {
  final rounds = ref.watch(voteRoundsProvider).value ?? const <VoteRound>[];
  for (final r in rounds) {
    if (r.isOpen) return r;
  }
  return null;
});

final myVotesProvider =
    FutureProvider.family<List<ClassVote>, String>((ref, roundId) async {
  return ref.read(voteRepositoryProvider).myVotes(roundId);
});

final voteTallyProvider =
    FutureProvider.family<List<VoteTallyRow>, String>((ref, roundId) async {
  return ref.read(voteRepositoryProvider).tally(roundId);
});

/// 라운드 안 학년별 진행 현황 — 학년마다 시험 일정이 달라 주차가 따로 간다.
final voteProgressProvider =
    FutureProvider.family<VoteProgress, String>((ref, roundId) async {
  return ref.read(voteRepositoryProvider).roundProgress(roundId);
});

/// 우리 학교에 있는 학년 (1~3 등) — 쉬는 기간을 학년별로 걸 때 사용.
final schoolGradesProvider = FutureProvider<List<int>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return const [1, 2, 3];
  return ref.read(voteRepositoryProvider).fetchGrades(profile!.schoolId!);
});

/// 투표 쉬는 기간 목록 (시험 기간 등).
final voteBlackoutsProvider = FutureProvider<List<VoteBlackout>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  return ref.read(voteRepositoryProvider).fetchBlackouts(profile!.schoolId!);
});

/// 진행 중 라운드 재미 힌트 — 교사·학생 화면 공용.
final voteHintProvider = FutureProvider<VoteHint>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return VoteHint(hasRound: false);
  return ref.read(voteRepositoryProvider).fetchHint();
});
