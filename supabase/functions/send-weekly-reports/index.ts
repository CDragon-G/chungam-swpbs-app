// supabase/functions/send-weekly-reports/index.ts
// 매주 각 학교 교사에게 지난 7일 성과 요약 리포트를 보낸다. (서비스성 메일)
// pg_cron이 주 1회(월요일 아침) 호출한다. weekly_report_batch()가 대상+지표를 준다.
//
// 시크릿 (공유): RESEND_API_KEY, RESEND_FROM, CRON_SECRET
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (기본 제공)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HOME = "https://jaramedu.kr";

interface Row {
  teacher_email: string;
  teacher_name: string | null;
  school_id: string;
  school_name: string;
  metrics: {
    students: number; active: number; checkins: number; avg_score: number;
    praise: number; kodr: number; cico_active: number; no_checkin: number;
    participation: number;
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function sendEmail(
  apiKey: string, from: string, to: string, subject: string, html: string,
): Promise<boolean> {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  return r.ok;
}

const stat = (label: string, value: string, color = "#1f2937") =>
  `<td style="padding:10px;text-align:center;border:1px solid #eef2f1;border-radius:8px">
     <div style="font-size:22px;font-weight:800;color:${color}">${value}</div>
     <div style="font-size:12px;color:#6b7280;margin-top:2px">${label}</div>
   </td>`;

function buildHtml(row: Row): string {
  const m = row.metrics;
  const name = row.teacher_name || "선생님";
  const attention = m.no_checkin > 0
    ? `<div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:10px;padding:14px;margin:16px 0">
         <b style="color:#c2410c">🔔 관심이 필요해요</b>
         <p style="margin:6px 0 0;font-size:14px;color:#7c2d12">이번 주 한 번도 체크인하지 않은 학생이 <b>${m.no_checkin}명</b> 있어요. 앱에서 확인하고 살짝 응원해 주세요.</p>
       </div>`
    : `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:14px;margin:16px 0">
         <b style="color:#065f46">🎉 모든 학생이 참여했어요!</b>
         <p style="margin:6px 0 0;font-size:14px;color:#047857">이번 주 전교생이 체크인에 참여했어요. 멋진 한 주였어요.</p>
       </div>`;

  return `
<div style="max-width:600px;margin:0 auto;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#1f2937;line-height:1.6">
  <div style="background:#10B981;padding:22px 24px;border-radius:12px 12px 0 0">
    <span style="color:#fff;font-size:20px;font-weight:800">자람 · 주간 리포트</span>
    <div style="color:#d1fae5;font-size:13px;margin-top:2px">${row.school_name} · 지난 7일 요약</div>
  </div>
  <div style="border:1px solid #e5e7eb;border-top:0;border-radius:0 0 12px 12px;padding:24px">
    <p style="margin:0 0 16px;font-size:15px">${name}님, 이번 주 우리 학교 자람 활동을 정리했어요.</p>

    <table style="width:100%;border-collapse:separate;border-spacing:6px">
      <tr>
        ${stat("참여율", m.participation + "%", "#10B981")}
        ${stat("참여 학생", m.active + "/" + m.students, "#10B981")}
        ${stat("체크인", m.checkins.toLocaleString("ko-KR"), "#1F3864")}
      </tr>
      <tr>
        ${stat("평균 준수율", m.avg_score + "%", "#1F3864")}
        ${stat("교사 칭찬", m.praise.toLocaleString("ko-KR"), "#7C3AED")}
        ${stat("CICO 진행", m.cico_active + "명", "#7C3AED")}
      </tr>
    </table>

    ${attention}

    ${m.kodr > 0 ? `<p style="font-size:14px;color:#6b7280;margin:6px 0">이번 주 K-ODR 기록 <b>${m.kodr}건</b> — Tier 2 지원이 필요한 학생이 있는지 살펴보세요.</p>` : ""}

    <div style="text-align:center;margin:20px 0 6px">
      <a href="${HOME}/admin.html" style="display:inline-block;background:#10B981;color:#fff;text-decoration:none;font-weight:700;padding:12px 26px;border-radius:8px">관리자에서 자세히 보기</a>
    </div>
    <p style="margin:14px 0 0;font-size:12px;color:#9ca3af">
      자람 · jaramedu.kr · 이 리포트가 불필요하시면 이 메일에 회신해 주세요.
    </p>
  </div>
</div>`.trim();
}

Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response("unauthorized", { status: 401 });
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM");
    if (!apiKey || !from) {
      return new Response(JSON.stringify({ error: "RESEND 미설정" }),
        { status: 500, headers: { "Content-Type": "application/json" } });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await supabase.rpc("weekly_report_batch");
    if (error) {
      return new Response(JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } });
    }

    const rows = (data ?? []) as Row[];
    let sent = 0;
    const failed: string[] = [];
    for (const row of rows) {
      const subject = `[자람] ${row.school_name} 주간 리포트`;
      const html = buildHtml(row);
      let ok = await sendEmail(apiKey, from, row.teacher_email, subject, html);
      if (!ok) {                       // 429 등 일시 실패 → 잠깐 쉬고 1회 재시도
        await sleep(1200);
        ok = await sendEmail(apiKey, from, row.teacher_email, subject, html);
      }
      if (ok) sent++; else failed.push(row.teacher_email);
      await sleep(600);                // Resend 초당 2건 제한 준수
    }

    return new Response(JSON.stringify({ candidates: rows.length, sent, failed }),
      { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
