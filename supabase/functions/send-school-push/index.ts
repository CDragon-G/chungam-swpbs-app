// supabase/functions/send-school-push/index.ts
// 새 공지 · 새 강화물을 휴대폰 알림으로 보낸다 (화면이 꺼져 있어도 온다).
// 앱이 공지 · 강화물을 등록한 직후 부른다. 호출자의 JWT 로 권한을 확인한다.
//
//   { kind: 'notice', id }      관리자 선생님 → 우리 학교 학생 · 선생님 (보낸 사람 제외)
//   { kind: 'store_item', id }  등록한 선생님 · 관리자 → 그 강화물을 볼 수 있는 학생
//
// 같은 공지 · 강화물은 한 번만 보낸다 (push_sent). 등록한 지 30분이 지난 것은 보내지 않는다.
// 필요한 시크릿: FCM_SERVICE_ACCOUNT (send-praise-push 와 같다)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── FCM 액세스 토큰 (send-vote-notice 와 같다) ────────────────
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

const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  try {
    const { kind, id } = await req.json();
    if ((kind !== "notice" && kind !== "store_item") || !id) {
      return json({ error: "kind, id 가 필요해요" }, 400);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: userData } = await admin.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    const uid = userData?.user?.id;
    if (!uid) return json({ error: "unauthorized" }, 401);

    const { data: me } = await admin
      .from("profiles")
      .select("school_id, role, teacher_role")
      .eq("user_id", uid)
      .maybeSingle();
    if (!me || me.role !== "teacher") return json({ error: "forbidden" }, 403);
    const isAdmin = me.teacher_role === "admin";

    // ── 무엇을 누구에게 ──
    let title = "";
    let body = "";
    let createdAt = "";
    let audience = "students";
    let grade: number | null = null;
    let classNum: number | null = null;
    let route = "/student/home";

    if (kind === "notice") {
      const { data: a } = await admin
        .from("announcements")
        .select("school_id, title, kind, is_active, created_at")
        .eq("id", id)
        .maybeSingle();
      if (!a || a.school_id !== me.school_id) return json({ error: "not found" }, 404);
      if (!isAdmin) return json({ error: "forbidden" }, 403);
      if (a.is_active === false) return json({ sent: 0, reason: "inactive" });
      title = a.kind === "event" ? "📣 학교 이벤트" : "📢 새 공지";
      body = a.title;
      createdAt = a.created_at;
      audience = "school";
    } else {
      const { data: it } = await admin
        .from("point_store_items")
        .select("*") // player_slots(077) 가 없는 서버에서도 되게 전부 받는다
        .eq("id", id)
        .maybeSingle();
      if (!it || it.school_id !== me.school_id) return json({ error: "not found" }, 404);
      if (!isAdmin && it.created_by !== uid) return json({ error: "forbidden" }, 403);
      if (it.is_active === false) return json({ sent: 0, reason: "inactive" });
      const isClass = it.grade != null && it.class_num != null;
      const sports = it.item_type === "group" && it.player_slots != null;
      title = sports
        ? (isClass ? "⚽ 우리 반 스포츠 경기 선수를 모아요" : "⚽ 스포츠 경기 선수를 모아요")
        : isClass ? "🎁 우리 반 새 강화물이 들어왔어요" : "🎁 교환소에 새 강화물이 들어왔어요";
      body = sports
        ? `${it.emoji ?? "⚽"} ${it.name} · 선수 ${it.player_slots}명 · 응원도 할 수 있어요`
        : it.item_type === "group"
        ? `${it.emoji ?? "🌱"} ${it.name} · 함께 키우기 목표 ${it.cost_points}P`
        : `${it.emoji ?? "🎁"} ${it.name} · ${it.cost_points}P`;
      createdAt = it.created_at;
      audience = isClass ? "class" : "students";
      grade = it.grade;
      classNum = it.class_num;
      route = "/student/store";
    }

    // 오래된 것은 보내지 않는다 (예전 공지를 다시 울리지 않게)
    if (Date.now() - new Date(createdAt).getTime() > 30 * 60 * 1000) {
      return json({ sent: 0, reason: "too old" });
    }

    // 한 번만 — 먼저 기록을 남기고, 이미 있으면 그만둔다
    const ref = `${kind}:${id}`;
    const { error: dupErr } = await admin
      .from("push_sent")
      .insert({ ref, school_id: me.school_id, sent_by: uid });
    if (dupErr) return json({ sent: 0, reason: "already sent" });

    const { data: tokens } = await admin.rpc("push_tokens_for", {
      p_school: me.school_id,
      p_audience: audience,
      p_grade: grade,
      p_class: classNum,
      p_except: uid,
    });
    const list = (tokens ?? []) as { token: string; role: string }[];

    const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const accessToken = await getAccessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const dead: string[] = [];
    const sendOne = async ({ token, role }: { token: string; role: string }) => {
      const r = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: {
              type: kind,
              route: role === "teacher" ? "/teacher/home" : route,
            },
            // 화면이 꺼져 있어도 바로 뜨게: 높은 우선순위 + 앱의 '자람 알림' 채널
            android: {
              priority: "high",
              notification: { channel_id: "jaram_push" },
            },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (r.ok) {
        sent++;
      } else if (r.status === 404) {
        // 앱을 지웠거나 만료된 기기(UNREGISTERED)만 지운다.
        // 400 은 메시지 형식 문제일 수도 있어 토큰을 건드리지 않는다.
        dead.push(token);
      }
    };
    // 학교 전체여도 오래 걸리지 않게 50개씩 한꺼번에
    for (let i = 0; i < list.length; i += 50) {
      await Promise.all(list.slice(i, i + 50).map(sendOne));
    }

    if (dead.length > 0) {
      await admin.from("device_tokens").delete().in("token", dead.slice(0, 500));
    }
    await admin.from("push_sent").update({ recipients: sent }).eq("ref", ref);

    return json({ sent, devices: list.length, removed: dead.length });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
