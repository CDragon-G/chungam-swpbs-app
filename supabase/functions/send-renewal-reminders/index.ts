// supabase/functions/send-renewal-reminders/index.ts
// 구독 만료가 다가온 학교에 갱신 안내 메일을 발송한다. (계좌이체 기반 · 자동갱신 opt-out)
// pg_cron이 매일 이 함수를 호출한다. DB의 renewal_batch()가 "오늘 보낼 대상"을 준다.
//
// 필요한 시크릿 (supabase secrets set):
//   RESEND_API_KEY   = Resend API 키
//   RESEND_FROM      = 보내는 사람 (예: "자람 <billing@jaramedu.kr>")  ← 도메인 인증 필요
//   OPERATOR_EMAIL   = 운영자 메일 (모든 발송에 bcc, 미설정 시 생략)
//   CRON_SECRET      = 크론 호출 검증용 공유 비밀 (미설정 시 검증 생략)
//   BILLING_BANK_INFO= 입금 안내 문구 (예: "국민 000000-00-000000 (예금주 신창용)")
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (기본 제공)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── 요금표 (admin.html PLAN_FEE와 동일) ──────────────────────
function feeFor(n: number): number {
  if (n <= 100) return 100000;
  if (n <= 300) return 180000;
  if (n <= 500) return 250000;
  if (n <= 1000) return 350000;
  return 450000;
}
const won = (n: number) => n.toLocaleString("ko-KR") + "원";

// ── 이메일 본문 빌더 ─────────────────────────────────────────
interface Row {
  school_id: string;
  school_name: string;
  contact_email: string | null;
  contact_name: string | null;
  auto_renew: boolean;
  stage: string;
  days_left: number;
  expires_at: string;
  grace_until: string | null;
  student_count: number;
  metrics: {
    active: number;
    checkins: number;
    avg_score: number;
    praise: number;
    kodr: number;
    cico_grad: number;
  };
}

function buildEmail(row: Row, bankInfo: string): { subject: string; html: string } {
  const m = row.metrics;
  const fee = feeFor(row.student_count || 0);
  const name = row.contact_name || "담당 선생님";
  const exp = row.expires_at;
  const auto = row.auto_renew;

  // 단계별 제목 · 인트로
  let subject = "";
  let intro = "";
  let cta = "";
  switch (row.stage) {
    case "d30":
      subject = `[자람] ${row.school_name}의 구독이 30일 뒤 갱신돼요`;
      intro = auto
        ? `${exp}에 다음 12개월 이용이 자동 갱신될 예정이에요. 아래 견적을 확인하시고, 예산·품의 준비를 미리 시작하시면 공백 없이 이어집니다.`
        : `${exp}에 구독이 종료돼요. 계속 이용하시려면 아래 견적으로 갱신을 준비해 주세요.`;
      cta = "지난 1년, 자람이 학교에 만든 변화를 먼저 확인해 보세요.";
      break;
    case "d7":
      subject = `[자람] ${row.school_name} 구독 갱신 D-7`;
      intro = auto
        ? `일주일 뒤(${exp}) 다음 12개월이 갱신될 예정이에요. 계좌이체·세금계산서 처리 시간을 고려해 지금 품의를 올려두시길 권해요.`
        : `일주일 뒤(${exp}) 구독이 종료돼요. 갱신을 원하시면 아래 안내로 진행해 주세요.`;
      cta = "아래 성과 요약을 품의 자료로 그대로 활용하셔도 좋아요.";
      break;
    case "d1":
      subject = `[자람] 내일 ${row.school_name} 구독이 갱신돼요`;
      intro = auto
        ? `내일(${exp}) 다음 12개월로 갱신될 예정이에요. 입금이 아직이라면 오늘 처리해 주시면 서비스가 끊기지 않아요.`
        : `내일(${exp}) 구독이 종료돼요. 오늘 갱신 처리하시면 공백 없이 이어집니다.`;
      cta = "학생들의 성장 기록이 그대로 유지돼요.";
      break;
    case "grace":
      subject = `[자람] ${row.school_name} 구독이 만료됐어요 (서비스는 유지 중)`;
      intro = `구독 기간이 ${exp}에 끝났지만, ${row.grace_until ?? ""}까지는 서비스를 그대로 유지해 드려요. 그 안에 갱신하시면 학생 데이터·기록이 하나도 손실 없이 이어집니다.`;
      cta = "유예 기간이 지나면 학생 체크인이 중단돼요. 지금 갱신을 권해요.";
      break;
    case "churn":
      subject = `[자람] ${row.school_name} 다시 시작하실 수 있어요`;
      intro = `유예 기간까지 갱신이 확인되지 않아 구독이 잠시 중단됐어요. 하지만 그동안의 학생 기록은 안전하게 보관돼 있고, 언제든 재개하면 그대로 이어집니다.`;
      cta = "다시 시작하시면 지난 1년의 데이터 위에서 곧바로 이어져요.";
      break;
    default:
      subject = `[자람] ${row.school_name} 구독 안내`;
      intro = `구독 관련 안내드려요.`;
  }

  const bank = bankInfo
    ? `<tr><td style="padding:6px 0;color:#6b7280">입금 계좌</td><td style="padding:6px 0;font-weight:600">${bankInfo}</td></tr>`
    : `<tr><td style="padding:6px 0;color:#6b7280">결제</td><td style="padding:6px 0">회신 주시면 견적서·계좌·세금계산서를 안내드려요.</td></tr>`;

  const html = `
<div style="max-width:560px;margin:0 auto;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#1f2937;line-height:1.6">
  <div style="background:#10B981;padding:20px 24px;border-radius:12px 12px 0 0">
    <span style="color:#fff;font-size:20px;font-weight:800">자람</span>
    <span style="color:#d1fae5;font-size:13px;margin-left:8px">학교 긍정적 행동지원 · SWPBS</span>
  </div>
  <div style="border:1px solid #e5e7eb;border-top:0;border-radius:0 0 12px 12px;padding:24px">
    <p style="margin:0 0 4px;font-size:15px">${name}님, 안녕하세요.</p>
    <p style="margin:0 0 16px;font-size:15px">${intro}</p>

    <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:16px 0">
      <p style="margin:0 0 10px;font-weight:700;color:#065f46">📊 지난 1년, ${row.school_name}의 자람 성과</p>
      <table style="width:100%;font-size:14px;border-collapse:collapse">
        <tr><td style="padding:4px 0;color:#6b7280">참여 학생</td><td style="padding:4px 0;text-align:right;font-weight:600">${m.active} / ${row.student_count}명</td></tr>
        <tr><td style="padding:4px 0;color:#6b7280">누적 체크인</td><td style="padding:4px 0;text-align:right;font-weight:600">${(m.checkins || 0).toLocaleString("ko-KR")}회</td></tr>
        <tr><td style="padding:4px 0;color:#6b7280">평균 규칙 준수율</td><td style="padding:4px 0;text-align:right;font-weight:600">${m.avg_score}%</td></tr>
        <tr><td style="padding:4px 0;color:#6b7280">교사 칭찬</td><td style="padding:4px 0;text-align:right;font-weight:600">${(m.praise || 0).toLocaleString("ko-KR")}회</td></tr>
        <tr><td style="padding:4px 0;color:#6b7280">CICO 졸업(자립)</td><td style="padding:4px 0;text-align:right;font-weight:600">${m.cico_grad}명</td></tr>
      </table>
      <p style="margin:10px 0 0;font-size:13px;color:#047857">${cta}</p>
    </div>

    <div style="border:1px solid #e5e7eb;border-radius:10px;padding:16px;margin:16px 0">
      <p style="margin:0 0 8px;font-weight:700">💳 갱신 견적 (12개월)</p>
      <table style="width:100%;font-size:14px;border-collapse:collapse">
        <tr><td style="padding:6px 0;color:#6b7280">학생 수</td><td style="padding:6px 0;font-weight:600">${row.student_count}명 기준</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">연 이용료</td><td style="padding:6px 0;font-weight:700;color:#10B981;font-size:16px">${won(fee)}</td></tr>
        ${bank}
      </table>
    </div>

    <p style="margin:16px 0 0;font-size:13px;color:#6b7280">
      문의: 이 메일에 회신하시거나 운영자에게 연락 주세요.<br>
      계좌이체·세금계산서·에듀파인 처리 모두 지원해 드려요.
    </p>
    <p style="margin:16px 0 0;font-size:12px;color:#9ca3af">
      자람 · jaramedu.kr · 학생 한 명의 성장을 함께 기록합니다 🌱
    </p>
  </div>
</div>`.trim();

  return { subject, html };
}

// ── Resend 발송 ──────────────────────────────────────────────
async function sendEmail(
  apiKey: string,
  from: string,
  to: string,
  bcc: string | null,
  subject: string,
  html: string,
): Promise<boolean> {
  const body: Record<string, unknown> = { from, to: [to], subject, html };
  if (bcc) body.bcc = [bcc];
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return r.ok;
}

// ── 메인 핸들러 ──────────────────────────────────────────────
Deno.serve(async (req) => {
  try {
    // 크론 공유 비밀 검증 (설정된 경우)
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response("unauthorized", { status: 401 });
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM");
    if (!apiKey || !from) {
      return new Response(
        JSON.stringify({ error: "RESEND_API_KEY / RESEND_FROM 미설정" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
    const operator = Deno.env.get("OPERATOR_EMAIL") ?? null;
    const bankInfo = Deno.env.get("BILLING_BANK_INFO") ?? "";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await supabase.rpc("renewal_batch");
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const rows = (data ?? []) as Row[];
    let sent = 0;
    let noEmail = 0;
    const failed: string[] = [];

    for (const row of rows) {
      if (!row.contact_email) {
        noEmail++;
        // 이메일이 없어도 단계는 기록해 다음 단계로 진행(무한 재시도 방지)
        await supabase.rpc("mark_renewal_stage", {
          p_school_id: row.school_id,
          p_stage: row.stage,
        });
        continue;
      }
      const { subject, html } = buildEmail(row, bankInfo);
      const ok = await sendEmail(apiKey, from, row.contact_email, operator, subject, html);
      if (ok) {
        sent++;
        await supabase.rpc("mark_renewal_stage", {
          p_school_id: row.school_id,
          p_stage: row.stage,
        });
      } else {
        failed.push(row.school_name);
      }
    }

    return new Response(
      JSON.stringify({ candidates: rows.length, sent, noEmail, failed }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
