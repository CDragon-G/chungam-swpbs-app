// =====================================================
// 충암중학교 SWPBS 일일 자기점검 - Google Apps Script
// 담당: 인성생활부 신창용 교사
// 배포: 웹앱 → 액세스: 누구나
// =====================================================

const SHEET_ID     = '1vAoD2bqbnx5_QyIpAHVtM2LVfjO1btsVH-lnnrc8p8s';
const SHEET_NAME   = 'SWPBS_DATA';
const PARENTS_NAME = 'PARENTS';
const TZ           = 'Asia/Seoul';

// 카테고리 구조 (index.html의 CATS와 반드시 동일하게 유지)
const CATS_CONFIG = [
  { key: '수업 3끝',  count: 3 },
  { key: '교실',     count: 3 },
  { key: '복도·계단', count: 3 },
  { key: '급식실',   count: 3 },
  { key: '화장실',   count: 3 },
];

// 시트 컬럼: A=제출시각  B=dateKey  C=학년  D=반  E=번호  F=점수  G=한마디  H=answersJSON

// ══════════════════════════════════════════════════════
//  라우터
// ══════════════════════════════════════════════════════
function doGet(e) {
  const action = (e.parameter.action || '').trim();
  let result;
  try {
    if      (action === 'submit')     result = handleSubmit(e);
    else if (action === 'getRanking') result = handleGetRanking(e);
    else if (action === 'getStats')   result = handleGetStats(e);
    else if (action === 'debug')      result = handleDebug(e);
    else result = { error: 'Unknown action: ' + action };
  } catch (err) {
    result = { error: err.message };
  }
  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

// ══════════════════════════════════════════════════════
//  제출 처리
// ══════════════════════════════════════════════════════
function handleSubmit(e) {
  const payload = JSON.parse(e.parameter.data);
  const { grade, room, num, answers, comment, dateKey } = payload;

  const vals  = Object.values(answers);
  const score = vals.length > 0
    ? Math.round(vals.filter(v => v === true).length / vals.length * 100)
    : 0;

  const ss    = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName(SHEET_NAME);

  // 당일 동일 학생 기존 행 삭제 후 새로 추가
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    const rows = sheet.getRange(2, 1, lastRow - 1, 8).getValues();
    for (let i = rows.length - 1; i >= 0; i--) {
      if (toDateKey(rows[i][1]) === dateKey &&
          String(rows[i][2]) === String(grade) &&
          String(rows[i][3]) === String(room)  &&
          String(rows[i][4]) === String(num)) {
        sheet.deleteRow(i + 2);
        break;
      }
    }
  }

  sheet.appendRow([
    new Date(), dateKey, grade, room, num,
    score, comment || '', JSON.stringify(answers)
  ]);
  SpreadsheetApp.flush();
  return { success: true, score };
}

// ══════════════════════════════════════════════════════
//  랭킹 조회
// ══════════════════════════════════════════════════════
function handleGetRanking(e) {
  const grade = (e.parameter.grade || '').trim();
  const room  = (e.parameter.room  || '').trim();
  const today = (e.parameter.dateKey || '').trim() || getTodayKey();

  let rows = getTodayRows(today);
  if (grade) rows = rows.filter(r => String(r[2]) === grade);
  if (room)  rows = rows.filter(r => String(r[3]) === room);
  rows = dedupRows(rows);

  const ranking = rows
    .map(r => ({
      name:    String(r[2]) + ' ' + String(r[3]) + ' ' + String(r[4]) + '번',
      score:   Number(r[5]),
      comment: String(r[6] || '').substring(0, 30),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 50);

  return { ranking };
}

// ══════════════════════════════════════════════════════
//  통계 조회
// ══════════════════════════════════════════════════════
function handleGetStats(e) {
  const grade   = (e.parameter.grade   || '').trim();
  const room    = (e.parameter.room    || '').trim();
  const myScore = Number(e.parameter.myScore) || 0;
  const today   = (e.parameter.dateKey || '').trim() || getTodayKey();

  const allRows    = getTodayRows(today);
  const classRows  = dedupRows(allRows.filter(r => String(r[2]) === grade && String(r[3]) === room));
  const gradeRows  = dedupRows(allRows.filter(r => String(r[2]) === grade));
  const schoolRows = dedupRows(allRows);

  const cScores = classRows.map(r => Number(r[5]));
  const gScores = gradeRows.map(r => Number(r[5]));
  const sScores = schoolRows.map(r => Number(r[5]));

  return {
    classAvg:         avg(cScores),
    gradeAvg:         avg(gScores),
    schoolAvg:        avg(sScores),
    classPercentile:  calcPercentile(myScore, cScores),
    gradePercentile:  calcPercentile(myScore, gScores),
    schoolPercentile: calcPercentile(myScore, sScores),
    classCount:       cScores.length,
    gradeCount:       gScores.length,
    schoolCount:      sScores.length,
    catClassAvgs:     calcCatAvgs(classRows),
    catSchoolAvgs:    calcCatAvgs(schoolRows),
  };
}

// ══════════════════════════════════════════════════════
//  디버그
// ══════════════════════════════════════════════════════
function handleDebug(e) {
  const today = (e.parameter.dateKey || '').trim() || getTodayKey();
  const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SHEET_NAME);
  if (!sheet) return { error: '시트 없음' };

  const all = sheet.getLastRow() > 1
    ? sheet.getRange(2, 1, sheet.getLastRow() - 1, 8).getValues()
    : [];
  const todayRows = all.filter(r => toDateKey(r[1]) === today);

  return {
    serverNow:  Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd HH:mm:ss'),
    filterKey:  today,
    totalRows:  all.length,
    todayRows:  todayRows.length,
    sample:     todayRows.slice(0, 10).map(r => ({
      raw:   String(r[1]),
      parsed: toDateKey(r[1]),
      grade: r[2], room: r[3], num: r[4], score: r[5]
    }))
  };
}

// ══════════════════════════════════════════════════════
//  유틸 함수
// ══════════════════════════════════════════════════════

function getTodayKey() {
  return Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd');
}

// Sheets가 날짜 문자열을 Date 객체로 자동 변환하는 문제 해결
function toDateKey(val) {
  if (!val) return '';
  if (val instanceof Date) return Utilities.formatDate(val, TZ, 'yyyy-MM-dd');
  return String(val).trim();
}

function getTodayRows(today) {
  const sheet = SpreadsheetApp.openById(SHEET_ID).getSheetByName(SHEET_NAME);
  if (!sheet || sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, 8).getValues()
    .filter(r => toDateKey(r[1]) === today);
}

function dedupRows(rows) {
  const seen = {};
  rows.forEach(r => {
    const key = String(r[2]) + '_' + String(r[3]) + '_' + String(r[4]);
    if (!seen[key] || r[0] > seen[key][0]) seen[key] = r;
  });
  return Object.values(seen);
}

function avg(arr) {
  if (!arr.length) return 0;
  return Math.round(arr.reduce((s, v) => s + Number(v), 0) / arr.length);
}

function calcPercentile(myScore, scores) {
  if (!scores.length) return 50;
  const below = scores.filter(s => Number(s) < myScore).length;
  return Math.max(1, Math.min(100, Math.round((1 - below / scores.length) * 100)));
}

function calcCatAvgs(rows) {
  const result = {};
  CATS_CONFIG.forEach((cat, ci) => {
    const scores = [];
    rows.forEach(r => {
      try {
        const ans = JSON.parse(r[7] || '{}');
        let yes = 0;
        for (let i = 0; i < cat.count; i++) {
          if (ans[String(ci) + '_' + String(i)] === true) yes++;
        }
        scores.push(Math.round(yes / cat.count * 100));
      } catch (_) {}
    });
    result[cat.key] = avg(scores);
  });
  return result;
}

// ══════════════════════════════════════════════════════
//  학부모 일일 알림 (매일 오후 6시)
// ══════════════════════════════════════════════════════
function sendDailyParentNotifications() {
  const ss           = SpreadsheetApp.openById(SHEET_ID);
  const parentsSheet = ss.getSheetByName(PARENTS_NAME);
  if (!parentsSheet || parentsSheet.getLastRow() < 2) return;

  const today     = getTodayKey();
  const todayRows = getTodayRows(today);
  const parents   = parentsSheet.getRange(2, 1, parentsSheet.getLastRow() - 1, 5).getValues();

  let sent = 0;
  for (const [grade, room, num, studentName, parentEmail] of parents) {
    if (!parentEmail || !grade || !room || !num || !studentName) continue;
    const studentRow = todayRows.find(
      r => String(r[2]) === String(grade) &&
           String(r[3]) === String(room)  &&
           String(r[4]) === String(num)
    );
    const classRows = todayRows.filter(
      r => String(r[2]) === String(grade) && String(r[3]) === String(room)
    );
    const subject = studentRow
      ? '[충암중 SWPBS] ' + today + ' ' + studentName + ' 학생 자기점검 결과'
      : '[충암중 SWPBS] ' + today + ' ' + studentName + ' 학생 자기점검 미제출 안내';
    const body = buildDailyEmail(
      studentName, grade, room, today,
      studentRow ? Number(studentRow[5]) : null,
      studentRow ? String(studentRow[6] || '') : '',
      avg(classRows.map(r => r[5])), classRows.length,
      studentRow ? JSON.parse(studentRow[7] || '{}') : null
    );
    try { MailApp.sendEmail(parentEmail, subject, body); sent++; }
    catch (err) { Logger.log('메일 실패: ' + parentEmail + ' / ' + err); }
  }
  Logger.log(today + ' 일일 알림: ' + sent + '건 발송');
}

// ══════════════════════════════════════════════════════
//  학부모 주간 요약 (매주 금요일 오후 5시)
// ══════════════════════════════════════════════════════
function sendWeeklyClassSummary() {
  const ss           = SpreadsheetApp.openById(SHEET_ID);
  const parentsSheet = ss.getSheetByName(PARENTS_NAME);
  const dataSheet    = ss.getSheetByName(SHEET_NAME);
  if (!parentsSheet || parentsSheet.getLastRow() < 2) return;
  if (!dataSheet || dataSheet.getLastRow() < 2) return;

  const allData  = dataSheet.getRange(2, 1, dataSheet.getLastRow() - 1, 8).getValues();
  const weekRows = getThisWeekRows(allData);
  const parents  = parentsSheet.getRange(2, 1, parentsSheet.getLastRow() - 1, 5).getValues();

  let sent = 0;
  for (const [grade, room, num, studentName, parentEmail] of parents) {
    if (!parentEmail || !studentName) continue;
    const myRows = weekRows.filter(
      r => String(r[2]) === String(grade) &&
           String(r[3]) === String(room)  &&
           String(r[4]) === String(num)
    );
    if (!myRows.length) continue;
    const classWeek    = weekRows.filter(r => String(r[2]) === String(grade) && String(r[3]) === String(room));
    const subject = '[충암중 SWPBS] 이번 주 ' + studentName + ' 학생 주간 요약';
    const body    = buildWeeklyEmail(studentName, myRows, avg(myRows.map(r=>r[5])), avg(classWeek.map(r=>r[5])));
    try { MailApp.sendEmail(parentEmail, subject, body); sent++; }
    catch (err) { Logger.log('주간 메일 실패: ' + err); }
  }
  Logger.log('주간 요약 ' + sent + '건 발송');
}

function getThisWeekRows(allData) {
  const now    = new Date();
  const day    = now.getDay();
  const monday = new Date(now);
  monday.setDate(now.getDate() - (day === 0 ? 6 : day - 1));
  monday.setHours(0, 0, 0, 0);
  return allData.filter(r => {
    const d = r[1] instanceof Date ? r[1] : new Date(r[1]);
    return !isNaN(d) && d >= monday && d <= now;
  });
}

// ══════════════════════════════════════════════════════
//  이메일 본문
// ══════════════════════════════════════════════════════
function buildDailyEmail(name, grade, room, date, score, comment, classAvg, classCount, answers) {
  if (score === null) {
    return '학부모님께\n\n' + date + ' ' + name + ' 학생이 오늘 SWPBS 자기점검을 제출하지 않았습니다.\n내일은 꼭 참여할 수 있도록 격려 부탁드립니다.\n\n충암중학교 인성생활부';
  }
  const diff  = score - classAvg;
  const emoji = score >= 90 ? '🌟' : score >= 75 ? '👍' : score >= 60 ? '😊' : '💪';
  let catLines = '';
  if (answers && Object.keys(answers).length > 0) {
    catLines = '\n[카테고리별 실천율]\n';
    CATS_CONFIG.forEach((cat, ci) => {
      let yes = 0;
      for (let i = 0; i < cat.count; i++) {
        if (answers[ci + '_' + i] === true) yes++;
      }
      catLines += '  ' + cat.key + ': ' + Math.round(yes / cat.count * 100) + '%\n';
    });
  }
  return '학부모님께\n\n' + date + ' ' + grade + ' ' + room + ' ' + name + ' 학생의 SWPBS 자기점검 결과입니다.\n\n' +
    '────────────────────────\n' +
    emoji + ' 오늘 실천율: ' + score + '%\n' +
    '우리 반 평균: ' + classAvg + '% (' + (diff >= 0 ? '+' : '') + diff + '%p) / 참여 ' + classCount + '명\n' +
    '────────────────────────\n' +
    catLines +
    (comment ? '\n학생 한마디: "' + comment + '"\n' : '') +
    '\n충암중학교 인성생활부';
}

function buildWeeklyEmail(name, myRows, weekAvg, classWeekAvg) {
  const diff     = weekAvg - classWeekAvg;
  const dayLines = myRows
    .sort((a, b) => toDateKey(a[1]).localeCompare(toDateKey(b[1])))
    .map(r => '  ' + toDateKey(r[1]) + '  ' + r[5] + '%')
    .join('\n');
  return '학부모님께\n\n이번 주 ' + name + ' 학생의 SWPBS 주간 요약입니다.\n\n' +
    '────────────────────────\n' +
    '참여 횟수: ' + myRows.length + '회 / 5일\n' +
    '이번 주 평균: ' + weekAvg + '%\n' +
    '우리 반 주간 평균: ' + classWeekAvg + '% (' + (diff >= 0 ? '+' : '') + diff + '%p)\n' +
    '────────────────────────\n' +
    '일별 실천율:\n' + dayLines +
    '\n\n충암중학교 인성생활부';
}

// ══════════════════════════════════════════════════════
//  트리거 설정 (최초 1회만 실행)
// ══════════════════════════════════════════════════════
function setupDailyTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'sendDailyParentNotifications')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('sendDailyParentNotifications')
    .timeBased().everyDays(1).atHour(18).create();
  Logger.log('일일 트리거 설정 완료 (매일 오후 6시)');
}

function setupWeeklyTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'sendWeeklyClassSummary')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('sendWeeklyClassSummary')
    .timeBased().onWeekDay(ScriptApp.WeekDay.FRIDAY).atHour(17).create();
  Logger.log('주간 트리거 설정 완료 (매주 금요일 오후 5시)');
}

// ══════════════════════════════════════════════════════
//  시트 초기화 (최초 1회만 실행)
// ══════════════════════════════════════════════════════
function initSheets() {
  const ss = SpreadsheetApp.openById(SHEET_ID);

  let data = ss.getSheetByName(SHEET_NAME);
  if (!data) {
    data = ss.insertSheet(SHEET_NAME);
    data.appendRow(['제출시각','dateKey','학년','반','번호','점수','한마디','answersJSON']);
    data.getRange(1,1,1,8).setFontWeight('bold').setBackground('#E2E8F0');
  }

  let parents = ss.getSheetByName(PARENTS_NAME);
  if (!parents) {
    parents = ss.insertSheet(PARENTS_NAME);
    parents.appendRow(['학년','반','번호','학생이름','학부모이메일']);
    parents.getRange(1,1,1,5).setFontWeight('bold').setBackground('#E2E8F0');
  }

  SpreadsheetApp.flush();
  Logger.log('시트 초기화 완료');
}
