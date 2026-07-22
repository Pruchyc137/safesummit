// SafeSummit — line-login
// แลก OAuth code ของ LINE Login → ได้ LINE userId → บันทึกลง users.line_uid
// ของ "ผู้ใช้ที่ล็อกอิน Supabase อยู่จริง" เท่านั้น (ยืนยันด้วย JWT)
//
// ทำไมต้องทำที่ server: channel secret ห้ามอยู่ในหน้าเว็บ + กันเว็บส่ง uid ปลอม
//
// Deploy:  supabase functions deploy line-login --no-verify-jwt
// ENV:
//   LINE_LOGIN_CHANNEL_ID       Channel ID ของ LINE Login channel
//   LINE_LOGIN_CHANNEL_SECRET   Channel secret ของ LINE Login channel
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY  (auto)

import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const j = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  // 1) ต้องล็อกอิน Supabase มาก่อน — ผูก LINE เข้ากับบัญชีนี้เท่านั้น
  const authHeader = req.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return j({ error: 'ยังไม่ได้เข้าสู่ระบบ' }, 401);
  const asUser = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: uErr } = await asUser.auth.getUser();
  if (uErr || !user) return j({ error: 'เซสชันไม่ถูกต้อง กรุณาเข้าสู่ระบบใหม่' }, 401);

  let body: { code?: string; redirect_uri?: string };
  try { body = await req.json(); } catch { return j({ error: 'bad json' }, 400); }
  if (!body.code || !body.redirect_uri) return j({ error: 'missing code/redirect_uri' }, 400);

  // 2) แลก code → access token กับ LINE (ใช้ channel secret ฝั่ง server)
  const form = new URLSearchParams({
    grant_type: 'authorization_code',
    code: body.code,
    redirect_uri: body.redirect_uri,
    client_id: Deno.env.get('LINE_LOGIN_CHANNEL_ID')!,
    client_secret: Deno.env.get('LINE_LOGIN_CHANNEL_SECRET')!,
  });
  const tokRes = await fetch('https://api.line.me/oauth2/v2.1/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  });
  if (!tokRes.ok) {
    const t = await tokRes.text();
    console.error('LINE token exchange failed', tokRes.status, t);
    return j({ error: 'เชื่อม LINE ไม่สำเร็จ (แลก token ไม่ได้)' }, 400);
  }
  const tok = await tokRes.json() as { access_token: string };

  // 3) เอา userId จริงจาก LINE (ไม่รับค่าจากฝั่งเว็บ)
  const profRes = await fetch('https://api.line.me/v2/profile', {
    headers: { Authorization: 'Bearer ' + tok.access_token },
  });
  if (!profRes.ok) return j({ error: 'ดึงโปรไฟล์ LINE ไม่สำเร็จ' }, 400);
  const prof = await profRes.json() as { userId: string; displayName?: string };
  if (!prof.userId) return j({ error: 'ไม่พบ LINE userId' }, 400);

  // 4) บันทึกลงโปรไฟล์ผู้ใช้ (service_role — client เขียนคอลัมน์นี้เองไม่ได้)
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  // กัน LINE บัญชีเดียวไปผูกกับหลาย account
  const { data: taken } = await admin.from('users').select('id').eq('line_uid', prof.userId).neq('id', user.id).maybeSingle();
  if (taken) return j({ error: 'บัญชี LINE นี้ถูกผูกกับผู้ใช้อื่นแล้ว' }, 409);

  const { error: wErr } = await admin.from('users').update({ line_uid: prof.userId }).eq('id', user.id);
  if (wErr) { console.error(wErr); return j({ error: 'บันทึกไม่สำเร็จ' }, 500); }

  // เติมให้การจองที่ยังรออนุมัติของผู้ใช้คนนี้ด้วย (เผื่อผูก LINE หลังจอง)
  await admin.from('bookings').update({ customer_line_uid: prof.userId })
    .eq('user_id', user.id).is('customer_line_uid', null).eq('approval_status', 'pending');

  return j({ ok: true, display_name: prof.displayName || null });
});
