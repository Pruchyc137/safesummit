// SafeSummit — line-webhook
// Webhook URL ของ OA ทีม (Messaging API → Webhook URL ชี้มาที่ function นี้)
// หน้าที่: รับ postback ปุ่มอนุมัติ/ปฏิเสธ → verify signature → เช็ค whitelist →
//          อัปเดต booking แบบ atomic (กันกดซ้ำ) → reply กลุ่มทีม → push แจ้งลูกค้า (ข้าม OA)
//
// Deploy:  supabase functions deploy line-webhook --no-verify-jwt
// ENV:
//   TEAM_LINE_CHANNEL_SECRET     verify x-line-signature ของ OA ทีม
//   TEAM_LINE_CHANNEL_TOKEN      reply เข้ากลุ่มทีม
//   CUSTOMER_LINE_CHANNEL_TOKEN  push แจ้งลูกค้า (OA ลูกค้า)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (auto)

import { createClient } from 'jsr:@supabase/supabase-js@2';

const REPLY = 'https://api.line.me/v2/bot/message/reply';
const PUSH  = 'https://api.line.me/v2/bot/message/push';

function j(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } }); }

// verify LINE signature: base64( HMAC-SHA256(channelSecret, rawBody) ) === x-line-signature
async function verifySig(secret: string, rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  // constant-time-ish compare
  if (expected.length !== signature.length) return false;
  let diff = 0; for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

async function lineReply(token: string, replyToken: string, text: string) {
  await fetch(REPLY, { method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text }] }) });
}
async function linePush(token: string, to: string, text: string) {
  const r = await fetch(PUSH, { method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
    body: JSON.stringify({ to, messages: [{ type: 'text', text }] }) });
  if (!r.ok) console.error('customer push failed', r.status, await r.text());
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  const raw = await req.text();
  // 1) ตรวจ signature ก่อนแตะอะไรทั้งสิ้น
  const ok = await verifySig(Deno.env.get('TEAM_LINE_CHANNEL_SECRET')!, raw, req.headers.get('x-line-signature'));
  if (!ok) return j({ error: 'bad signature' }, 401);

  let body: { events?: any[] };
  try { body = JSON.parse(raw); } catch { return j({ error: 'bad json' }, 400); }

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const teamToken = Deno.env.get('TEAM_LINE_CHANNEL_TOKEN')!;
  const custToken = Deno.env.get('CUSTOMER_LINE_CHANNEL_TOKEN')!;

  for (const ev of body.events || []) {
    // ── ช่วยตอนติดตั้ง: log groupId/userId ทุก event (ดูใน Function Logs เพื่อกรอก TEAM_LINE_GROUP_ID + whitelist)
    console.log('[line-webhook] event', ev.type, 'groupId=', ev.source?.groupId, 'userId=', ev.source?.userId,
      ev.type === 'message' ? ('text=' + (ev.message?.text || '')) : '');
    if (ev.type !== 'postback') continue;                    // สนใจเฉพาะปุ่มกด (event อื่น log ไว้ช่วย setup)
    const params = new URLSearchParams(ev.postback?.data || '');
    const action = params.get('action');                     // approve | reject
    const bookingId = params.get('bookingId');
    const uid = ev.source?.userId;
    if (!action || !bookingId || !uid) continue;

    // 2) whitelist — ต้องอยู่ใน authorized_approvers เท่านั้น
    const { data: appr } = await supabase.from('authorized_approvers')
      .select('name, active').eq('line_uid', uid).maybeSingle();
    if (!appr || appr.active === false) {
      if (ev.replyToken) await lineReply(teamToken, ev.replyToken, '⛔ คุณไม่มีสิทธิ์อนุมัติการจอง (ไม่อยู่ใน whitelist)');
      continue;
    }

    // 3) อัปเดตแบบ atomic — RPC เปลี่ยน pending → decision ครั้งเดียว (กัน race/กดซ้ำ)
    const decision = action === 'approve' ? 'approved' : 'rejected';
    const { data: result, error } = await supabase.rpc('line_decide_booking',
      { p_booking_id: bookingId, p_decision: decision, p_by: appr.name, p_by_uid: uid });
    if (error) {
      console.error('rpc error', error);
      if (ev.replyToken) await lineReply(teamToken, ev.replyToken, '⚠️ เกิดข้อผิดพลาด: ' + error.message);
      continue;
    }

    const r = result as { changed: boolean; status: string; by: string; customer_line_uid?: string; booking_ref?: string };
    const ref = r.booking_ref || bookingId;
    const when = new Date().toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'short', timeStyle: 'short' });

    // 4) reply เข้ากลุ่มทีม
    if (!r.changed) {
      if (ev.replyToken) await lineReply(teamToken, ev.replyToken,
        `ℹ️ การจอง ${ref} ถูก${r.status === 'approved' ? 'อนุมัติ' : 'ปฏิเสธ'}ไปแล้วโดย ${r.by || '-'}`);
      continue;
    }
    const word = decision === 'approved' ? '✅ อนุมัติแล้ว' : '❌ ปฏิเสธแล้ว';
    if (ev.replyToken) await lineReply(teamToken, ev.replyToken, `${word}\nการจอง ${ref}\nโดย ${appr.name} · ${when}`);

    // 5) แจ้งลูกค้า (ข้าม OA — ใช้ token ลูกค้า) ถ้ามี uid ลูกค้า
    if (r.customer_line_uid) {
      const msg = decision === 'approved'
        ? `🎉 การจอง ${ref} ของคุณได้รับการยืนยันจากทีม SafeSummit แล้ว! ทีมงานจะติดต่อรายละเอียดถัดไปเร็วๆ นี้`
        : `ขออภัยครับ การจอง ${ref} ไม่สามารถดำเนินการต่อได้ในขณะนี้ หากมีข้อสงสัยติดต่อทีมงานได้เลย`;
      await linePush(custToken, r.customer_line_uid, msg);
    }
  }

  return j({ ok: true });   // LINE ต้องได้ 200 เสมอ
});
