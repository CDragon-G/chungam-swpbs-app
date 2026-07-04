// supabase/functions/send-operator-alert/index.ts
// 새 도입 신청이 들어오면 운영자에게 즉시 알림 메일을 보낸다.
// DB 트리거(purchase_requests AFTER INSERT)가 pg_net으로 이 함수를 호출한다.
//
// 시크릿 (공유): RESEND_API_KEY, RESEND_FROM, OPERATOR_EMAIL, CRON_SECRET
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (기본 제공)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HOME = "https://jaramedu.kr";

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

const row = (k: string, v: string) =>
  `<tr><td style="padding:5px 0;color:#6b7280">${k}</td><td style="padding:5px 0;font-weight:600">${v || "-"}</td></tr>`;

Deno.serve(async (req) => {
  try {
    // 트리거 전용 — 공유 비밀 검증
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response("unauthorized", { status: 401 });
    }

    const { request_id } = await req.json();
    if (!request_id) {
      return new Response(JSON.stringify({ error: "request_id 누락" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: pr } = await supabase
      .from("purchase_requests").select("*").eq("id", request_id).single();
    if (!pr) {
      return new Response(JSON.stringify({ error: "신청 없음" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM");
    const operator = Deno.env.get("OPERATOR_EMAIL");
    if (!apiKey || !from || !operator) {
      return new Response(JSON.stringify({ error: "RESEND/OPERATOR 미설정" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    const html = `
<div style="max-width:560px;margin:0 auto;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#1f2937;line-height:1.6">
  <div style="background:#1F3864;padding:20px 24px;border-radius:12px 12px 0 0">
    <span style="color:#fff;font-size:18px;font-weight:800">🔔 새 도입 신청</span>
  </div>
  <div style="border:1px solid #e5e7eb;border-top:0;border-radius:0 0 12px 12px;padding:24px">
    <p style="margin:0 0 12px;font-size:15px"><b>${pr.school_name}</b>에서 자람 도입을 신청했어요.</p>
    <table style="width:100%;font-size:14px;border-collapse:collapse">
      ${row("학교", `${pr.school_name} (${pr.level ?? "-"} · ${pr.region ?? "-"})`)}
      ${row("담당자", `${pr.contact_name ?? "-"} · ${pr.contact_email}`)}
      ${row("연락처", pr.contact_phone ?? "-")}
      ${row("학생 수", pr.student_count ? pr.student_count + "명" : "-")}
      ${row("요금제", pr.plan ?? "-")}
      ${row("문의사항", pr.message ?? "-")}
    </table>
    <div style="text-align:center;margin:20px 0 4px">
      <a href="${HOME}/admin.html" style="display:inline-block;background:#1F3864;color:#fff;text-decoration:none;font-weight:700;padding:11px 26px;border-radius:8px">관리자에서 처리하기</a>
    </div>
    <p style="margin:14px 0 0;font-size:12px;color:#9ca3af">입금 확인 후 승인하면 담당자에게 환영 메일이 자동 발송돼요.</p>
  </div>
</div>`.trim();

    const ok = await sendEmail(apiKey, from, operator, `[자람] 새 도입 신청 — ${pr.school_name}`, html);
    return new Response(JSON.stringify({ sent: ok }), {
      status: ok ? 200 : 502, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
