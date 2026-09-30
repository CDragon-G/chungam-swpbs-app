"""마이그레이션이 실제 DB에 적용됐는지 확인하는 SQL 을 만든다.

supabase/migrations/*.sql 에서 만드는 표 · 컬럼 · 함수를 모아,
DB 에 없는 것만 돌려주는 쿼리를 tool/check_applied.sql 로 쓴다.
Supabase SQL 에디터에 붙여 넣고 실행하면 빠진 것만 나온다 (없으면 0행).

    python tool/check_applied.py            # 전체
    python tool/check_applied.py 069        # 069 까지만 (아직 안 올린 파일 제외)
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIG = ROOT / 'supabase' / 'migrations'
OUT = ROOT / 'tool' / 'check_applied.sql'

upto = sys.argv[1] if len(sys.argv) > 1 else None

ident = r'(?:public\.)?"?([a-z_][a-z0-9_]*)"?'
re_table = re.compile(r'create\s+table\s+(?:if\s+not\s+exists\s+)?' + ident, re.I)
re_func = re.compile(r'create\s+(?:or\s+replace\s+)?function\s+' + ident + r'\s*\(', re.I)
re_alter = re.compile(r'alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?' + ident + r'(.*?);', re.I | re.S)
re_addcol = re.compile(r'add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?', re.I)
re_drop_table = re.compile(r'drop\s+table\s+(?:if\s+exists\s+)?' + ident, re.I)
re_drop_func = re.compile(r'drop\s+function\s+(?:if\s+exists\s+)?' + ident, re.I)
re_drop_col = re.compile(r'drop\s+column\s+(?:if\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?', re.I)


def strip_comments(sql: str) -> str:
    return re.sub(r'--[^\n]*', '', sql)


tables, funcs, cols = {}, {}, {}
for f in sorted(MIG.glob('*.sql')):
    tag = f.name[:3]
    if upto and tag > upto:
        continue
    sql = strip_comments(io.open(f, encoding='utf-8').read())
    # 파일 안에서 나오는 순서대로: 만들기와 지우기를 차례로 반영한다
    events = []
    for m in re_table.finditer(sql):
        events.append((m.start(), 'table+', m.group(1), None))
    for m in re_drop_table.finditer(sql):
        events.append((m.start(), 'table-', m.group(1), None))
    for m in re_func.finditer(sql):
        events.append((m.start(), 'func+', m.group(1), None))
    for m in re_drop_func.finditer(sql):
        events.append((m.start(), 'func-', m.group(1), None))
    for m in re_alter.finditer(sql):
        body = m.group(2)
        for c in re_addcol.finditer(body):
            events.append((m.start() + c.start(), 'col+', m.group(1), c.group(1)))
        for c in re_drop_col.finditer(body):
            events.append((m.start() + c.start(), 'col-', m.group(1), c.group(1)))
    for _, kind, name, col in sorted(events):
        if kind == 'table+':
            tables[name] = f.name
        elif kind == 'table-':
            tables.pop(name, None)
        elif kind == 'func+':
            funcs[name] = f.name
        elif kind == 'func-':
            funcs.pop(name, None)  # 같은 파일에서 다시 만들면 위에서 다시 채워진다
        elif kind == 'col+':
            cols[(name, col)] = f.name
        elif kind == 'col-':
            cols.pop((name, col), None)

# 지워진 표의 컬럼은 확인하지 않는다
cols = {k: v for k, v in cols.items() if k[0] in tables or not k[0].startswith('_')}

rows = []
for t, src in sorted(tables.items(), key=lambda x: x[1]):
    rows.append(f"  ('{src}', 'table', '{t}', to_regclass('public.{t}') is not null)")
for (t, c), src in sorted(cols.items(), key=lambda x: x[1]):
    rows.append(
        f"  ('{src}', 'column', '{t}.{c}', exists (select 1 from information_schema.columns"
        f" where table_schema = 'public' and table_name = '{t}' and column_name = '{c}'))")
for fn, src in sorted(funcs.items(), key=lambda x: x[1]):
    rows.append(
        f"  ('{src}', 'function', '{fn}', exists (select 1 from pg_proc p"
        f" join pg_namespace n on n.oid = p.pronamespace"
        f" where n.nspname = 'public' and p.proname = '{fn}'))")

sql = (
    "-- 마이그레이션 적용 확인 (tool/check_applied.py 가 만든 파일)\n"
    "-- 결과가 0행이면 모두 적용된 것. 나온 행의 '파일' 을 SQL 에디터에서 실행하면 된다.\n"
    "select file as \"파일\", kind as \"종류\", name as \"이름\"\n"
    "  from (values\n" + ",\n".join(rows) + "\n  ) as t(file, kind, name, ok)\n"
    " where not ok\n"
    " order by file, kind, name;\n"
)
io.open(OUT, 'w', encoding='utf-8', newline='\n').write(sql)
print(f'{OUT.relative_to(ROOT)}: 표 {len(tables)} · 컬럼 {len(cols)} · 함수 {len(funcs)}'
      + (f' (≤{upto})' if upto else ''))
