"""앱 → 서버 호출 정합성 검사.

    python tool/audit_queries.py

1) 표를 직접 읽을 때 없는 컬럼을 쓰는지 (Postgres 42703)
2) 없는 서버 함수(rpc)를 부르는지 (42883)

둘 다 앱에서는 '데이터 처리 중 오류가 발생했어요' 로만 보여서 원인을 찾기 어렵다.
실제로 '선생님 관리' 화면이 profiles.name (없는 컬럼) 을 읽어서 열리지 않았다.
컴파일러는 이런 것을 잡아주지 못하므로, 화면을 추가하거나 조회를 고친 뒤 한 번 돌린다.

supabase/migrations/*.sql 을 읽어 스키마를 만들고 lib/**.dart 를 훑는다.
"""
import io
import os
import re
import glob

SQL_DIR = r'C:/dev/pbs_plus/supabase/migrations'
LIB_DIR = r'C:/dev/pbs_plus/lib'


def strip_sql_comments(sql):
    sql = re.sub(r'--[^\n]*', '', sql)
    return re.sub(r'/\*.*?\*/', '', sql, flags=re.S)


schema = {}      # table/view -> set(cols) ; 뷰는 None (컬럼 검사 안 함)
functions = set()

CREATE_T = re.compile(r'create table (?:if not exists )?(?:public\.)?([a-z_0-9]+)\s*\(', re.I)
CREATE_V = re.compile(r'create (?:or replace )?view (?:public\.)?([a-z_0-9]+)', re.I)
ALTER = re.compile(
    r'alter table (?:only )?(?:public\.)?([a-z_0-9]+)\s+add column (?:if not exists )?([a-z_0-9]+)',
    re.I | re.S)
FUNC = re.compile(r'create (?:or replace )?function (?:public\.)?([a-z_0-9]+)\s*\(', re.I)

for path in sorted(glob.glob(os.path.join(SQL_DIR, '*.sql'))):
    sql = strip_sql_comments(io.open(path, encoding='utf-8').read())
    for m in FUNC.finditer(sql):
        functions.add(m.group(1).lower())
    for m in CREATE_V.finditer(sql):
        schema[m.group(1).lower()] = None
    for m in CREATE_T.finditer(sql):
        table = m.group(1).lower()
        i, depth, body = m.end(), 1, []
        while i < len(sql) and depth > 0:
            ch = sql[i]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    break
            body.append(ch)
            i += 1
        cols = schema.get(table)
        if cols is None and table in schema:
            continue      # 뷰로 먼저 잡힌 이름
        cols = schema.setdefault(table, set())
        depth2, line = 0, ''
        for ch in ''.join(body) + ',':
            if ch == '(':
                depth2 += 1
            elif ch == ')':
                depth2 -= 1
            if ch == ',' and depth2 == 0:
                tok = line.strip().split()
                if tok:
                    first = tok[0].lower()
                    if first not in ('primary', 'unique', 'foreign', 'check',
                                     'constraint', 'exclude', 'like'):
                        cols.add(first)
                line = ''
            else:
                line += ch
    for m in ALTER.finditer(sql):
        t = m.group(1).lower()
        if schema.get(t) is not None:
            schema.setdefault(t, set()).add(m.group(2).lower())

FROM = re.compile(r"\.from\('([a-z_0-9]+)'\)")
SELECT = re.compile(r"\.select\(\s*'([^']*)'")
FILTER = re.compile(
    r"\.(?:eq|neq|gt|gte|lt|lte|like|ilike|is_|inFilter|contains|order|not)\(\s*'([a-z_0-9]+)'")
RPC = re.compile(r"\.rpc\(\s*'([a-z_0-9]+)'")

col_problems, rpc_problems = [], []
checked_q = checked_r = 0

for path in glob.glob(os.path.join(LIB_DIR, '**', '*.dart'), recursive=True):
    src = io.open(path, encoding='utf-8').read()
    rel = os.path.relpath(path, LIB_DIR)

    for m in RPC.finditer(src):
        checked_r += 1
        if m.group(1).lower() not in functions:
            rpc_problems.append((rel, m.group(1)))

    for m in FROM.finditer(src):
        table = m.group(1)
        chunk = src[m.end():m.end() + 700]
        nxt = FROM.search(chunk)
        if nxt:
            chunk = chunk[:nxt.start()]
        cols = set()
        sm = SELECT.search(chunk)
        if sm:
            for raw in sm.group(1).split(','):
                c = raw.strip()
                if '(' in c or ':' in c or c in ('*', ''):
                    continue
                cols.add(c.lower())
        for fm in FILTER.finditer(chunk):
            cols.add(fm.group(1).lower())
        if not cols:
            continue
        checked_q += 1
        known = schema.get(table, 'MISSING')
        if known == 'MISSING':
            col_problems.append((rel, table, '표/뷰 없음', sorted(cols)))
        elif known is None:
            continue      # 뷰는 컬럼을 파싱하지 않는다
        else:
            missing = sorted(c for c in cols if c not in known)
            if missing:
                col_problems.append((rel, table, '없는 컬럼', missing))

print(f'표 직접 조회 {checked_q}건, rpc 호출 {checked_r}건 검사')
print(f'컬럼 문제 {len(col_problems)}건')
for p in col_problems:
    print('   ', p[0], '|', p[1], '|', p[2], p[3])
print(f'없는 서버 함수 {len(rpc_problems)}건')
for p in sorted(set(rpc_problems)):
    print('   ', p[0], '|', p[1])
