import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/school_code_generator.dart';
import '../models/roster_entry.dart';
import '../models/school.dart';
import '../models/school_rule.dart';

class SchoolRepository {
  SchoolRepository();

  SupabaseClient get _c => SupabaseService.client;

  Future<School> createSchool({
    required String name,
    required String region,
    required String level,
  }) async {
    final user = _c.auth.currentUser;
    if (user == null) throw StateError('로그인 상태가 아닙니다.');

    // Prevent duplicate schools: check if same (name, region, level) exists
    final dup = await _c
        .from('schools')
        .select('school_code')
        .eq('name', name)
        .eq('region', region)
        .eq('level', level)
        .maybeSingle();
    if (dup != null) {
      throw StateError(
        '이미 등록된 학교예요.\n'
        '"기존 학교 참여" 탭에서 학교 코드 ${dup['school_code']}로 참여해주세요.\n'
        '(학교 코드는 첫 번째로 가입한 교사에게 문의)',
      );
    }

    final code = await SchoolCodeGenerator.generateUnique();
    final teacherCode = SchoolCodeGenerator.generateTeacherCode();
    final inserted = await _c
        .from('schools')
        .insert({
          'name': name,
          'region': region,
          'level': level,
          'school_code': code,
          'teacher_code': teacherCode,
          'created_by': user.id,
        })
        .select()
        .single();
    final school = School.fromMap(inserted);
    // seed default rule template
    await _c.rpc('seed_default_rules', params: {'p_school_id': school.id});
    return school;
  }

  /// 학생 가입용: school_code로 학교 조회.
  Future<School?> findByCode(String code) async {
    final row = await _c
        .from('schools')
        .select()
        .eq('school_code', code)
        .maybeSingle();
    return row == null ? null : School.fromMap(row);
  }

  /// 교사 가입용: teacher_code로 학교 조회 (기존 학교 참여 시).
  Future<School?> findByTeacherCode(String code) async {
    final row = await _c
        .from('schools')
        .select()
        .eq('teacher_code', code)
        .maybeSingle();
    return row == null ? null : School.fromMap(row);
  }

  Future<School?> findById(String id) async {
    final row = await _c.from('schools').select().eq('id', id).maybeSingle();
    return row == null ? null : School.fromMap(row);
  }

  Future<List<SchoolRule>> fetchRules(String schoolId) async {
    final rows = await _c
        .from('school_rules')
        .select()
        .eq('school_id', schoolId)
        .eq('is_active', true)
        .order('order_index');
    return rows.map((m) => SchoolRule.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<SchoolRule>> fetchAllRules(String schoolId) async {
    final rows = await _c
        .from('school_rules')
        .select()
        .eq('school_id', schoolId)
        .order('order_index');
    return rows.map((m) => SchoolRule.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<SchoolRule> addRule({
    required String schoolId,
    required String space,
    required String category,
    required String ruleText,
    required int orderIndex,
  }) async {
    final inserted = await _c
        .from('school_rules')
        .insert({
          'school_id': schoolId,
          'space': space,
          'category': category,
          'rule_text': ruleText,
          'order_index': orderIndex,
          'is_active': true,
        })
        .select()
        .single();
    return SchoolRule.fromMap(inserted);
  }

  Future<SchoolRule> updateRule(String id, Map<String, dynamic> patch) async {
    final row = await _c
        .from('school_rules')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return SchoolRule.fromMap(row);
  }

  Future<void> deleteRule(String id) async {
    await _c.from('school_rules').delete().eq('id', id);
  }

  Future<void> reorderRules(List<SchoolRule> rules) async {
    for (var i = 0; i < rules.length; i++) {
      await _c
          .from('school_rules')
          .update({'order_index': i})
          .eq('id', rules[i].id);
    }
  }

  // Announcements
  Future<List<Map<String, dynamic>>> fetchAnnouncements(String schoolId) async {
    final rows = await _c
        .from('announcements')
        .select()
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> postAnnouncement({
    required String schoolId,
    required String title,
    required String body,
  }) async {
    final user = _c.auth.currentUser;
    if (user == null) throw StateError('로그인 상태가 아닙니다.');
    final inserted = await _c
        .from('announcements')
        .insert({
          'school_id': schoolId,
          'title': title,
          'body': body,
          'created_by': user.id,
        })
        .select()
        .single();
    return inserted;
  }

  Future<void> deleteAnnouncement(String id) async {
    await _c.from('announcements').delete().eq('id', id);
  }

  // Teacher: list students for a school
  Future<List<Map<String, dynamic>>> fetchStudents(String schoolId) async {
    final rows = await _c
        .from('profiles')
        .select()
        .eq('school_id', schoolId)
        .eq('role', 'student')
        .order('grade')
        .order('class_num')
        .order('student_num');
    return List<Map<String, dynamic>>.from(rows);
  }

  // List all teachers in a school (for admin permission management)
  Future<List<Map<String, dynamic>>> fetchTeachers(String schoolId) async {
    final rows = await _c
        .from('profiles')
        .select()
        .eq('school_id', schoolId)
        .eq('role', 'teacher')
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  // Admin only: change a teacher's role via RPC (includes safety checks)
  Future<void> setTeacherRole({
    required String profileId,
    required String newRole, // 'admin' | 'regular'
  }) async {
    await _c.rpc('set_teacher_role', params: {
      'p_profile_id': profileId,
      'p_new_role': newRole,
    });
  }

  // ── 학생 명단 (roster) ──────────────────────────────────────

  /// 명단 일괄 업로드 (교사 전용). 등록된 행 수를 반환.
  Future<int> uploadRoster({
    required String schoolId,
    required List<RosterDraftRow> rows,
  }) async {
    final res = await _c.rpc('upload_roster', params: {
      'p_school_id': schoolId,
      'p_rows': rows.map((r) => r.toJson()).toList(),
    });
    return (res as int?) ?? rows.length;
  }

  /// 학교 명단 조회 (PIN 포함, 교사만).
  Future<List<RosterEntry>> fetchRoster(String schoolId) async {
    final rows = await _c
        .from('student_roster')
        .select()
        .eq('school_id', schoolId)
        .order('grade')
        .order('class_num')
        .order('student_num');
    return List<Map<String, dynamic>>.from(rows)
        .map(RosterEntry.fromMap)
        .toList();
  }

  /// 가입 전 명단·PIN 검증. 일치하면 학생 이름 반환, 아니면 예외.
  Future<String> verifyRosterPin({
    required String schoolId,
    required int grade,
    required int classNum,
    required int studentNum,
    required String pin,
  }) async {
    final res = await _c.rpc('verify_roster_pin', params: {
      'p_school_id': schoolId,
      'p_grade': grade,
      'p_class_num': classNum,
      'p_student_num': studentNum,
      'p_pin': pin,
    });
    return res as String;
  }

  /// 가입 완료 후 명단 잠금 (재가입 방지).
  Future<void> claimRoster({
    required String schoolId,
    required int grade,
    required int classNum,
    required int studentNum,
    required String pin,
  }) async {
    await _c.rpc('claim_roster', params: {
      'p_school_id': schoolId,
      'p_grade': grade,
      'p_class_num': classNum,
      'p_student_num': studentNum,
      'p_pin': pin,
    });
  }

  /// 명단 한 줄 추가 (교사 직접 입력용). uploadRoster 1건 버전.
  Future<void> addRosterEntry({
    required String schoolId,
    required int grade,
    required int classNum,
    required int studentNum,
    required String name,
  }) async {
    await _c.rpc('upload_roster', params: {
      'p_school_id': schoolId,
      'p_rows': [
        {
          'grade': grade,
          'class_num': classNum,
          'student_num': studentNum,
          'name': name,
        }
      ],
    });
  }

  /// 명단 개별 삭제.
  Future<void> deleteRosterEntry(String id) async {
    await _c.rpc('delete_roster_entry', params: {'p_id': id});
  }

  /// 학교 전체 명단 삭제. 삭제된 수 반환.
  Future<int> clearRoster(String schoolId) async {
    final res = await _c.rpc('clear_roster', params: {'p_school_id': schoolId});
    return (res as int?) ?? 0;
  }
}
