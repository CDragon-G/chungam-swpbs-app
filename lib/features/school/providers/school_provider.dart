import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/profile_provider.dart';
import '../data/school_repository.dart';
import '../models/roster_entry.dart';
import '../models/school.dart';
import '../models/school_rule.dart';

final schoolRepositoryProvider = Provider<SchoolRepository>((_) => SchoolRepository());

final schoolProvider = FutureProvider<School?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return null;
  final repo = ref.read(schoolRepositoryProvider);
  return repo.findById(profile!.schoolId!);
});

final schoolRulesProvider = FutureProvider<List<SchoolRule>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchRules(profile!.schoolId!);
});

final allSchoolRulesProvider = FutureProvider<List<SchoolRule>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchAllRules(profile!.schoolId!);
});

final announcementsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchAnnouncements(profile!.schoolId!);
});

final schoolStudentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchStudents(profile!.schoolId!);
});

final schoolTeachersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchTeachers(profile!.schoolId!);
});

final schoolRosterProvider = FutureProvider<List<RosterEntry>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final repo = ref.read(schoolRepositoryProvider);
  return repo.fetchRoster(profile!.schoolId!);
});
