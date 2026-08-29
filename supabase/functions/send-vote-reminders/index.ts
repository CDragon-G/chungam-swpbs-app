// supabase/functions/send-vote-reminders/index.ts
// 매주 금요일 퇴청 전, 수업맛집 투표가 열려 있는 학교의 교사들에게 푸시 알림.
// pg_cron(금요일 KST)이 호출한다. 시크릿: FCM_SERVICE_ACCOUNT, CRON_SECRET.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── FCM 액세스 토큰 (send-praise-push와 동일) ────────────────
async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = sa.private_key.replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const bin = atob(pem);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  const key = await crypto.subtle.importKey(
    "pkcs8", buf.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  let s = "";
  for (const b of sig) s += String.fromCharCode(b);
  const signed = `${unsigned}.${btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signed,
    }),
  });
  return (await resp.json()).access_token;
}

Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response("unauthorized", { status: 401 });
    }

    const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 열린 라운드가 있는 학교들
    const { data: rounds, error } = await supabase
      .from("vote_rounds")
      .select("school_id, title, votes_per_week")
      .eq("status", "open");
    if (error) throw new Error(error.message);
    if (!rounds || rounds.length === 0) {
      return new Response(JSON.stringify({ schools: 0, sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);
    const url =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    // 오늘(KST) 날짜 — 학교별 수업일 판정에 사용
    const todayKst = new Date(Date.now() + 9 * 3600 * 1000)
      .toISOString()
      .slice(0, 10);

    let sent = 0;
    let skipped = 0;
    for (const round of rounds) {
      // 공휴일·방학·재량휴업일에는 알림을 보내지 않는다
      const { data: isSchoolDay } = await supabase.rpc("is_school_day", {
        p_school: round.school_id,
        p_date: todayKst,
      });
      if (isSchoolDay === false) {
        skipped++;
        continue;
      }

      // 학년마다 시험 일정이 다르다. 오늘 투표할 수 있는 학년이 하나도 없으면
      // (예: 전 학년 시험 주간) 알림을 보내지 않는다.
      const { data: ctx } = await supabase.rpc("vote_reminder_grades", {
        p_school: round.school_id,
      });
      const openGrades: number[] = ctx?.open ?? [];
      const pausedGrades: { grade: number; label: string }[] = ctx?.paused ?? [];
      if (ctx && openGrades.length === 0) {
        skipped++;
        continue;
      }

      // 일부 학년만 쉬면 어느 학년이 대상인지 알려준다
      let scope = "";
      if (ctx && pausedGrades.length > 0) {
        scope = ` · 오늘은 ${openGrades.join("·")}학년만 (` +
          pausedGrades.map((p) => `${p.grade}학년 ${p.label}`).join(", ") + ")";
      }

      // 그 학교 교사들
      const { data: teachers } = await supabase
        .from("profiles")
        .select("user_id")
        .eq("school_id", round.school_id)
        .eq("role", "teacher");
      const ids = (teachers ?? []).map((t) => t.user_id);
      if (ids.length === 0) continue;

      const { data: tokens } = await supabase
        .from("device_tokens")
        .select("token")
        .in("user_id", ids);

      for (const { token } of tokens ?? []) {
        const r = await fetch(url, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: "🍽️ 수업맛집 투표 시간이에요!",
                body:
                  `이번 주 수업 규칙을 가장 잘 지킨 학급에 투표해주세요 (주 ${round.votes_per_week}표) · ${round.title}${scope}`,
              },
              data: { type: "vote_reminder" },
              android: { priority: "high" },
              apns: { payload: { aps: { sound: "default" } } },
            },
          }),
        });
        if (r.ok) sent++;
      }
    }

    return new Response(JSON.stringify({ schools: rounds.length, sent, skipped }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
