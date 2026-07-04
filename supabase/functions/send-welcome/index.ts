// supabase/functions/send-welcome/index.ts
// 도입 신청 승인 직후 담당자에게 환영 메일(학교코드·교사코드·시작가이드)을 자동 발송한다.
// admin.html이 approve_purchase_request 성공 후 이 함수를 호출한다. (거래성 메일 → 수신동의 불필요)
//
// 시크릿 (send-renewal-reminders와 공유):
//   RESEND_API_KEY, RESEND_FROM, OPERATOR_EMAIL
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (기본 제공)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPERATOR = "toyswar987@naver.com";
const HOME = "https://jaramedu.kr";
const IOS_URL = "https://apps.apple.com/app/id6780309774";
const ANDROID_URL = "https://play.google.com/store/apps/details?id=com.jaram.app";

async function sendEmail(
  apiKey: string, from: string, to: string, bcc: string | null,
  subject: string, html: string,
): Promise<boolean> {
  const body: Record<string, unknown> = { from, to: [to], subject, html };
  if (bcc) body.bcc = [bcc];
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return r.ok;
}

function buildHtml(pr: Record<string, string>): string {
  const name = pr.contact_name || "담당 선생님";
  return `
<div style="max-width:560px;margin:0 auto;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#1f2937;line-height:1.6">
  <div style="background:#10B981;padding:22px 24px;border-radius:12px 12px 0 0">
    <span style="color:#fff;font-size:20px;font-weight:800">자람</span>
    <span style="color:#d1fae5;font-size:13px;margin-left:8px">학교 긍정적 행동지원 · SWPBS</span>
  </div>
  <div style="border:1px solid #e5e7eb;border-top:0;border-radius:0 0 12px 12px;padding:24px">
    <p style="margin:0 0 4px;font-size:16px;font-weight:700">${pr.school_name} 도입을 환영합니다 🌱</p>
    <p style="margin:0 0 16px;font-size:15px">${name}님, 결제가 확인되어 학교 코드를 발급해 드렸어요. 아래 코드로 바로 시작하실 수 있어요.</p>

    <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:18px;margin:16px 0">
      <table style="width:100%;font-size:15px;border-collapse:collapse">
        <tr><td style="padding:6px 0;color:#6b7280">학생 가입 코드</td>
            <td style="padding:6px 0;text-align:right;font-weight:800;font-size:20px;letter-spacing:1px;color:#065f46">${pr.school_code}</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">교사 가입 코드</td>
            <td style="padding:6px 0;text-align:right;font-weight:800;font-size:20px;letter-spacing:1px;color:#7C3AED">${pr.teacher_code}</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">이용 기간</td>
            <td style="padding:6px 0;text-align:right;font-weight:600">발급일로부터 1년</td></tr>
      </table>
    </div>

    <div style="border:1px solid #e5e7eb;border-radius:10px;padding:18px;margin:16px 0">
      <p style="margin:0 0 10px;font-weight:700">🚀 3단계로 시작하기</p>
      <ol style="margin:0;padding-left:20px;font-size:14px">
        <li style="margin-bottom:6px"><b>교사</b> — 자람 앱 설치 → 회원가입(교사) → 교사 코드 <b>${pr.teacher_code}</b> 입력</li>
        <li style="margin-bottom:6px"><b>명단 등록</b> — <a href="${HOME}/admin.html" style="color:#10B981">학교 관리자 페이지</a>에서 전교생 명단(엑셀) 업로드</li>
        <li><b>학생</b> — 자람 앱 설치 → 회원가입(학생) → 학교 코드 <b>${pr.school_code}</b> + 본인 PIN으로 가입</li>
      </ol>
    </div>

    <div style="text-align:center;margin:20px 0">
      <a href="${IOS_URL}" style="display:inline-block;background:#111827;color:#fff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:8px;margin:4px">📱 App Store</a>
      <a href="${ANDROID_URL}" style="display:inline-block;background:#10B981;color:#fff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:8px;margin:4px">▶️ Google Play</a>
    </div>

    <p style="margin:16px 0 0;font-size:13px;color:#6b7280">
      견적서·세금계산서가 필요하시면 이 메일에 회신해 주세요.<br>
      궁금하신 점은 언제든 편하게 문의 주세요.
    </p>
    <p style="margin:16px 0 0;font-size:12px;color:#9ca3af">자람 · jaramedu.kr · 학생 한 명의 성장을 함께 기록합니다 🌱</p>
  </div>
</div>`.trim();
}

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 호출자 = 운영자 검증 (admin.html이 운영자 JWT로 호출)
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData } = await supabase.auth.getUser(token);
    if (!userData?.user || userData.user.email !== OPERATOR) {
      return new Response(JSON.stringify({ error: "운영자만 호출할 수 있어요." }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    const { request_id } = await req.json();
    if (!request_id) {
      return new Response(JSON.stringify({ error: "request_id 누락" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    const { data: pr } = await supabase
      .from("purchase_requests").select("*").eq("id", request_id).single();
    if (!pr) {
      return new Response(JSON.stringify({ error: "신청을 찾을 수 없어요." }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }
    if (pr.status !== "approved" || !pr.school_code) {
      return new Response(JSON.stringify({ error: "아직 승인되지 않은 신청이에요." }), {
        status: 409, headers: { "Content-Type": "application/json" },
      });
    }
    if (!pr.contact_email) {
      return new Response(JSON.stringify({ error: "담당자 이메일이 없어요." }), {
        status: 422, headers: { "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM");
    if (!apiKey || !from) {
      return new Response(JSON.stringify({ error: "RESEND 미설정" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }
    const operator = Deno.env.get("OPERATOR_EMAIL") ?? null;

    const subject = `[자람] ${pr.school_name} 도입이 완료됐어요 — 학교 코드 안내`;
    const ok = await sendEmail(apiKey, from, pr.contact_email, operator, subject, buildHtml(pr));

    return new Response(JSON.stringify({ sent: ok, to: pr.contact_email }), {
      status: ok ? 200 : 502,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
