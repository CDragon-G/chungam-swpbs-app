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
