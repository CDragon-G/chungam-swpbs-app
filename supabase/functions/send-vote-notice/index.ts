// supabase/functions/send-vote-notice/index.ts
// 관리자 교사가 [투표 안내 보내기] 버튼을 누르면 우리 학교 교사들에게 푸시.
// 호출자의 JWT로 본인이 그 학교 관리자 교사인지 확인한 뒤에만 보낸다.
// 시크릿: FCM_SERVICE_ACCOUNT

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
    const { title, body } = await req.json();
    if (!body) return new Response("no body", { status: 400 });

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return new Response("unauthorized", { status: 401 });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 누가 눌렀는지 확인
    const { data: userData } = await admin.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    const uid = userData?.user?.id;
    if (!uid) return new Response("unauthorized", { status: 401 });

    // 관리자 교사만 발송할 수 있다
    const { data: me } = await admin
      .from("profiles")
      .select("school_id, role, teacher_role")
      .eq("user_id", uid)
      .maybeSingle();
    if (!me || me.role !== "teacher" || me.teacher_role !== "admin") {
      return new Response("forbidden", { status: 403 });
    }

    // 우리 학교 교사들의 기기
    const { data: teachers } = await admin
      .from("profiles")
      .select("user_id")
      .eq("school_id", me.school_id)
      .eq("role", "teacher");
    const ids = (teachers ?? []).map((t) => t.user_id);
    if (ids.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: tokens } = await admin
      .from("device_tokens")
      .select("token")
      .in("user_id", ids);

    const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const accessToken = await getAccessToken(sa);
    const url =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
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
              title: title || "🍽️ 수업맛집 투표 안내",
              body,
            },
            data: { type: "vote_notice", route: "/teacher/vote" },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (r.ok) sent++;
    }

    return new Response(JSON.stringify({ sent, teachers: ids.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
