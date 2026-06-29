// supabase/functions/send-praise-push/index.ts
// 칭찬이 등록되면 그 학생의 모든 기기로 FCM 푸시를 발송한다.
// DB 트리거(pg_net)가 이 함수를 호출한다.
//
// 필요한 시크릿 (supabase secrets set):
//   FCM_SERVICE_ACCOUNT  = Firebase 서비스 계정 JSON (한 줄)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (기본 제공)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── JWT로 FCM 액세스 토큰 발급 ──────────────────────────────
async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${enc(header)}.${enc(claim)}`;

  // PEM private key → CryptoKey
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const der = pemToDer(pem);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const signed = `${unsigned}.${arrToB64Url(new Uint8Array(sig))}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signed,
    }),
  });
  const json = await resp.json();
  return json.access_token;
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

function arrToB64Url(arr: Uint8Array): string {
  let s = "";
  for (const b of arr) s += String.fromCharCode(b);
  return btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

// ── 메인 핸들러 ──────────────────────────────────────────────
Deno.serve(async (req) => {
  try {
    const { student_id, message } = await req.json();
    if (!student_id) {
      return new Response("missing student_id", { status: 400 });
    }

    const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const projectId = sa.project_id;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 학생의 기기 토큰 조회
    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", student_id);

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no tokens" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);
    const url =
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    for (const { token } of tokens) {
      const body = {
        message: {
          token,
          notification: {
            title: "칭찬을 받았어요! 💚",
            body: message ?? "선생님께 칭찬을 받았어요.",
          },
          data: { type: "praise" },
          android: { priority: "high" },
          apns: {
            payload: { aps: { sound: "default", badge: 1 } },
          },
        },
      };
      const r = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      if (r.ok) sent++;
    }

    return new Response(JSON.stringify({ sent }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
