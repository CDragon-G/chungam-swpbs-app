// =====================================================
// 충암중학교 SWPBS 일일 자기점검 - Google Apps Script
// 배포: 웹앱 → 액세스: 누구나
// 트리거 설정: setupDailyTrigger() 와 setupWeeklyTrigger() 를
//             Apps Script 편집기에서 직접 한 번씩 실행하세요.
// =====================================================

const SHEET_ID     = '1vAoD2bqbnx5_QyIpAHVtM2LVfjO1btsVH-lnnrc8p8s'; // ← Google Sheet ID 입력
const SHEET_NAME   = 'SWPBS_DATA';
const PARENTS_NAME = 'PARENTS';

// 카테고리 구조 (index.html의 CATS와 반드시 동일하게 유지)
const CATS_CONFIG = [
  { key: '수업 3끝',  count: 3 },
  { key: '교실',     count: 3 },
  { key: '복도·계단', count: 3 },
  { key: '급식실',   count: 3 },
  { key: '화장실',   count: 3 },
];

// ─── 라우터 ────────────────────────────────────────────
function doGet(e) {
  const action = (e.parameter.action || '').trim();
  let result;
  try {
    switch (action) {
      case 'submit':      result = handleSubmit(e.parameter.data); break;
      case 'getRanking':  result = handleGetRanking(e.parameter.grade || '', e.parameter.room || ''); break;
      case 'getStats':    result = handleGetStats(
                            e.parameter.grade   || '',
                            e.parameter.room    || '',
                            e.parameter.num     || '',
                            Number(e.parameter.myScore) || 0
                          ); break;
      default: result = { error: 'Unknown action: ' + action };
    }
  } catch (err) {
    result = { error: err.toString() };
  }
  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

// ─── 제출 ────────────────────────────────────────────
function handleSubmit(dataStr) {
  const data = JSON.parse(dataStr);
  const { grade, room, num, answers, comment, dateKey } = data;

  const vals  = Object.values(answers);
  const score = vals.length > 0
    ? Math.round(vals.filter(v => v === true).length / vals.length * 100)
    : 0;

  const ss    = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName(SHEET_NAME);
  const rowKey = `${grade}_${room}_${num}_${dateKey}`;

  // 당일 중복 → 덮어쓰기
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    const rows = sheet.getRange(2, 1, lastRow - 1, 8).getValues();
    for (let i = 0; i < rows.length; i++) {
      if (`${rows[i][2]}_${rows[i][3]}_${rows[i][4]}_${rows[i][1]}` === rowKey) {
        sheet.getRange(i + 2, 1, 1, 8).setValues([[
          new Date(), dateKey, grade, room, num, score, comment, JSON.stringify(answers)
        ]]);
        return { success: true, key: rowKey, score, overwrite: true };
      }
    }
  }

  sheet.appendRow([new Date(), dateKey, grade, room, num, score, comment, JSON.stringify(answers)]);
  return { success: true, key: rowKey, score };
}

// ─── 랭킹 조회 ────────────────────────────────────────
// grade+room 지정 → 우리 반 / grade만 → 학년 / 둘 다 빈값 → 전교
function handleGetRanking(grade, room) {
  const rows = getTodayRows(getTodayKey());
  let filtered = rows;
  if (grade) filtered = filtered.filter(r => r[2] === grade);
  if (room)  filtered = filtered.filter(r => r[3] === room);

  const ranking = filtered
    .map(r => ({
      name:    `${r[2]} ${r[3]} ${r[4]}번`,
      score:   Number(r[5]),
      comment: String(r[6] || '').substring(0, 30),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 40);

  return { ranking };
}

// ─── 통계 조회 ────────────────────────────────────────
function handleGetStats(grade, room, num, myScore) {
  const rows       = getTodayRows(getTodayKey());
  const classRows  = rows.filter(r => r[2] === grade && r[3] === room);
  const gradeRows  = rows.filter(r => r[2] === grade);
  const schoolRows = rows;

  const classAvg  = avg(classRows.map(r => r[5]));
  const gradeAvg  = avg(gradeRows.map(r => r[5]));
  const schoolAvg = avg(schoolRows.map(r => r[5]));

  // 상위 X% = 100 - percentileBelow
  const classPercentile  = calcPercentile(myScore, classRows.map(r => r[5]));
  const gradePercentile  = calcPercentile(myScore, gradeRows.map(r => r[5]));
  const schoolPercentile = calcPercentile(myScore, schoolRows.map(r => r[5]));

  // 카테고리별 우리 반 평균
  const catClassAvgs  = calcCatAvgs(classRows);
  const catSchoolAvgs = calcCatAvgs(schoolRows);

  return {
    classAvg,  gradeAvg,  schoolAvg,
    classPercentile, gradePercentile, schoolPercentile,
    catClassAvgs, catSchoolAvgs,
    classCount:  classRows.length,
    gradeCount:  gradeRows.length,
    schoolCount: schoolRows.length,
  };
}

// ─── 학부모 일일 알림 ──────────────────────────────────
// setupDailyTrigger()를 Apps Script 편집기에서 한 번 직접 실행하세요.
function setupDailyTrigger() {
  // 기존 트리거 정리
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'sendDailyParentNotifications')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('sendDailyParentNotifications')
    .timeBased()
    .everyDays(1)
    .atHour(18)   // 오후 6시
    .create();
  Logger.log('일일 알림 트리거 설정 완료 (매일 오후 6시)');
}

// ─── 학부모 주간 요약 ──────────────────────────────────
// setupWeeklyTrigger()를 Apps Script 편집기에서 한 번 직접 실행하세요.
function setupWeeklyTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'sendWeeklyClassSummary')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('sendWeeklyClassSummary')
    .timeBased()
    .onWeekDay(ScriptApp.WeekDay.FRIDAY)
    .atHour(17)   // 금요일 오후 5시
    .create();
  Logger.log('주간 요약 트리거 설정 완료 (매주 금요일 오후 5시)');
}

function sendDailyParentNotifications() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const parentsSheet = ss.getSheetByName(PARENTS_NAME);
  if (!parentsSheet || parentsSheet.getLastRow() < 2) {
    Logger.log('PARENTS 시트가 없거나 데이터가 없습니다.');
    return;
  }

  const today     = getTodayKey();
  const todayRows = getTodayRows(today);
  const parents   = parentsSheet.getRange(2, 1, parentsSheet.getLastRow() - 1, 5).getValues();
  // 컬럼: A=학년, B=반, C=번호, D=학생이름, E=학부모이메일

  let sent = 0, skipped = 0;
  for (const [grade, room, num, studentName, parentEmail] of parents) {
    if (!parentEmail || !grade || !room || !num || !studentName) { skipped++; continue; }

    const studentRow = todayRows.find(
      r => r[2] === grade && r[3] === room && String(r[4]) === String(num)
    );
    const classRows  = todayRows.filter(r => r[2] === grade && r[3] === room);
    const classAvg   = avg(classRows.map(r => r[5]));
    const classCount = classRows.length;

    const subject = studentRow
      ? `[충암중 SWPBS] ${today} ${studentName} 학생 자기점검 결과`
      : `[충암중 SWPBS] ${today} ${studentName} 학생 자기점검 미제출 안내`;

    const body = buildDailyEmail(
      studentName, grade, room, today,
      studentRow ? Number(studentRow[5]) : null,
      studentRow ? String(studentRow[6] || '') : '',
      classAvg, classCount,
      studentRow ? JSON.parse(studentRow[7] || '{}') : null
    );

    try {
      MailApp.sendEmail(parentEmail, subject, body);
      sent++;
    } catch (e) {
      Logger.log(`메일 발송 실패 (${parentEmail}): ${e}`);
    }
  }
  Logger.log(`${today} 일일 알림 발송 완료: ${sent}건 / 미발송: ${skipped}건`);
}

function sendWeeklyClassSummary() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const parentsSheet = ss.getSheetByName(PARENTS_NAME);
  if (!parentsSheet || parentsSheet.getLastRow() < 2) return;

  const sheet = ss.getSheetByName(SHEET_NAME);
  if (sheet.getLastRow() < 2) return;

  const allData  = sheet.getRange(2, 1, sheet.getLastRow() - 1, 7).getValues();
  const weekRows = getThisWeekRows(allData);
  const parents  = parentsSheet.getRange(2, 1, parentsSheet.getLastRow() - 1, 5).getValues();

  let sent = 0;
  for (const [grade, room, num, studentName, parentEmail] of parents) {
    if (!parentEmail || !studentName) continue;
    const myRows = weekRows.filter(
      r => r[2] === grade && r[3] === room && String(r[4]) === String(num)
    );
    if (!myRows.length) continue;

    const weekAvg  = avg(myRows.map(r => r[5]));
    const classWeek = weekRows.filter(r => r[2] === grade && r[3] === room);
    const classWeekAvg = avg(classWeek.map(r => r[5]));

    const subject = `[충암중 SWPBS] 주간 자기점검 요약 - ${studentName}`;
    const body    = buildWeeklyEmail(studentName, grade, room, myRows, weekAvg, classWeekAvg);

    try {
      MailApp.sendEmail(parentEmail, subject, body);
      sent++;
    } catch (e) {
      Logger.log(`주간 메일 실패 (${parentEmail}): ${e}`);
    }
  }
  Logger.log(`주간 알림 발송 완료: ${sent}건`);
}

// ─── 이메일 본문 생성 ──────────────────────────────────
function buildDailyEmail(name, grade, room, date, score, comment, classAvg, classCount, answers) {
  if (score === null) {
    return `학부모님 안녕하세요.

오늘(${date}) ${name} 학생이 SWPBS 자기점검을 아직 제출하지 않았습니다.
오늘 제출이 완료된 경우 이 메일은 무시하셔도 됩니다.

충암중학교 인성생활부 드림`;
  }

  const diff    = score - classAvg;
  const diffStr = (diff >= 0 ? '+' : '') + diff + '%';
  const emoji   = score >= 90 ? '🌟' : score >= 75 ? '👍' : score >= 60 ? '😊' : '💪';
  const msg     = score >= 90 ? '매우 잘 실천했습니다! 오늘 꼭 칭찬해 주세요.'
                : score >= 75 ? '잘 실천했습니다.'
                : score >= 60 ? '보통 수준으로 실천했습니다.'
                : '조금 더 노력이 필요합니다. 오늘 함께 이야기 나눠 주세요.';

  // 카테고리별 점수 계산
  let catLines = '';
  if (answers) {
    catLines = '\n카테고리별 실천율:\n';
    CATS_CONFIG.forEach((cat, ci) => {
      let yes = 0;
      for (let i = 0; i < cat.count; i++) {
        if (answers[`${ci}_${i}`] === true) yes++;
      }
      const pct = Math.round(yes / cat.count * 100);
      const bar = '█'.repeat(Math.round(pct / 10)) + '░'.repeat(10 - Math.round(pct / 10));
      catLines += `  ${cat.key.padEnd(6)}  [${bar}]  ${pct}%\n`;
    });
  }

  return `학부모님 안녕하세요.

오늘(${date}) ${grade} ${room} ${name} 학생의 SWPBS 일일 자기점검 결과입니다.

━━━━━━━━━━━━━━━━━━━━━━━━
${emoji} 오늘 실천율: ${score}%
👥 우리 반 평균: ${classAvg}% (${diffStr}) / 오늘 제출 ${classCount}명
━━━━━━━━━━━━━━━━━━━━━━━━
${catLines}
${comment ? `💬 학생 한마디: "${comment}"\n` : ''}
${msg}

충암중학교 인성생활부 드림
※ 이 메일은 자동 발송됩니다. 문의: 인성생활부`;
}

function buildWeeklyEmail(name, grade, room, myRows, weekAvg, classWeekAvg) {
  const diff    = weekAvg - classWeekAvg;
  const diffStr = (diff >= 0 ? '+' : '') + diff + '%';
  const dayLines = myRows.map(r => `  ${r[1]}  ${r[5]}%`).join('\n');

  return `학부모님 안녕하세요.

이번 주 ${name} 학생의 SWPBS 자기점검 주간 요약입니다.

━━━━━━━━━━━━━━━━━━━━━━━━
📅 제출 일수: ${myRows.length}일 / 5일
📊 주간 평균 실천율: ${weekAvg}%
👥 우리 반 주간 평균: ${classWeekAvg}% (${diffStr})
━━━━━━━━━━━━━━━━━━━━━━━━
일별 실천율:
${dayLines}

다음 주도 좋은 행동 습관을 이어가도록 응원해 주세요!

충암중학교 인성생활부 드림
※ 이 메일은 매주 금요일 오후 자동 발송됩니다.`;
}

// ─── 시트 초기화 (최초 1회 실행) ──────────────────────
function initSheets() {
  const ss = SpreadsheetApp.openById(SHEET_ID);

  // SWPBS_DATA 시트
  let data = ss.getSheetByName(SHEET_NAME);
  if (!data) data = ss.insertSheet(SHEET_NAME);
  if (data.getLastRow() === 0) {
    data.appendRow(['제출시각', '날짜키', '학년', '반', '번호', '점수', '한줄소감', '응답JSON']);
    data.getRange(1, 1, 1, 8).setFontWeight('bold').setBackground('#E2E8F0');
  }

  // PARENTS 시트
  let parents = ss.getSheetByName(PARENTS_NAME);
  if (!parents) {
    parents = ss.insertSheet(PARENTS_NAME);
    parents.appendRow(['학년', '반', '번호', '학생이름', '학부모이메일']);
    parents.getRange(1, 1, 1, 5).setFontWeight('bold').setBackground('#E2E8F0');
    // 예시 행
    parents.appendRow(['1학년', '1반', '1', '홍길동', 'parent@example.com']);
    parents.getRange(2, 1, 1, 5).setFontStyle('italic').setFontColor('#9CA3AF');
  }

  Logger.log('시트 초기화 완료');
}

// ─── 헬퍼 ────────────────────────────────────────────
function getTodayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function getTodayRows(today) {
  const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SHEET_NAME);
  if (sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, 8).getValues()
    .filter(r => r[1] === today);
}

function avg(arr) {
  if (!arr.length) return 0;
  return Math.round(arr.reduce((s, v) => s + Number(v), 0) / arr.length);
}

// 내 점수가 peers 중 상위 X%인지 계산
// 반환값: 상위 X% (낮을수록 상위권)
function calcPercentile(myScore, scores) {
  if (!scores.length) return 50;
  const below = scores.filter(s => Number(s) < myScore).length;
  const top   = Math.round((1 - below / scores.length) * 100);
  return Math.max(1, Math.min(100, top));
}

// answers JSON에서 카테고리별 평균 점수 계산
function calcCatAvgs(rows) {
  const result = {};
  CATS_CONFIG.forEach((cat, ci) => {
    const catScores = [];
    rows.forEach(row => {
      try {
        const ans = JSON.parse(row[7] || '{}');
        let yes = 0;
        for (let i = 0; i < cat.count; i++) {
          if (ans[`${ci}_${i}`] === true) yes++;
        }
        catScores.push(Math.round(yes / cat.count * 100));
      } catch (e) { /* skip malformed */ }
    });
    result[cat.key] = avg(catScores);
  });
  return result;
}

function getThisWeekRows(allData) {
  const now    = new Date();
  const day    = now.getDay();
  const monday = new Date(now);
  monday.setDate(now.getDate() - (day === 0 ? 6 : day - 1));
  monday.setHours(0, 0, 0, 0);
  return allData.filter(r => {
    const d = new Date(r[1]);
    return !isNaN(d) && d >= monday && d <= now;
  });
}