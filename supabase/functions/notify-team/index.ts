// SafeSummit — notify-team
// Trigger: Supabase Database Webhook (INSERT on public.bookings)
// หน้าที่: ส่ง LINE Flex Message เข้ากลุ่มไลน์ทีม พร้อมปุ่ม อนุมัติ/ปฏิเสธ (postback ฝัง bookingId)
//
// Deploy:  supabase functions deploy notify-team --no-verify-jwt
// ENV ที่ต้องตั้ง:
//   TEAM_LINE_CHANNEL_TOKEN   token ของ OA ทีม (Messaging API → Channel access token)
//   TEAM_LINE_GROUP_ID        groupId ของกลุ่มไลน์ทีม (ได้จาก webhook event ตอน OA ถูกเชิญเข้ากลุ่ม)
//   NOTIFY_WEBHOOK_SECRET     สตริงลับ ตั้งใน Database Webhook header 'x-webhook-secret' ให้ตรงกัน (กันคนอื่นยิง)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (Supabase ใส่ให้อัตโนมัติ)

import { createClient } from 'jsr:@supabase/supabase-js@2';

const LINE_PUSH = 'https://api.line.me/v2/bot/message/push';

function j(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}
const fmtBaht = (n: number) => '฿' + (Number(n) || 0).toLocaleString('en-US');

Deno.serve(async (req) => {
  if (req.method !== 'POST') return j({ error: 'method not allowed' }, 405);

  // 1) กันคนอื่นยิง — ตรวจ secret ที่ตั้งไว้ใน Database Webhook header
  const secret = Deno.env.get('NOTIFY_WEBHOOK_SECRET');
  if (secret && req.headers.get('x-webhook-secret') !== secret) {
    return j({ error: 'unauthorized' }, 401);
  }

  let payload: { type?: string; record?: Record<string, unknown> };
  try { payload = await req.json(); } catch { return j({ error: 'bad json' }, 400); }

  // Supabase webhook: { type:'INSERT', table, record, old_record }
  if (payload.type !== 'INSERT' || !payload.record) return j({ ok: true, skipped: 'not an insert' });
  const b = payload.record;
  const bookingId = String(b.id);

  // 2) ดึงรายละเอียดเพิ่ม (ชื่อทริป + ชื่อลูกค้า) ด้วย service_role
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  let tripName = '-', customer = '-', startDate = '';
  try {
    if (b.trip_id) {
      const { data: t } = await supabase.from('trips').select('name_th, start_date').eq('id', b.trip_id).maybeSingle();
      tripName = t?.name_th || '-'; startDate = t?.start_date || '';
    }
    if (b.user_id) {
      const { data: u } = await supabase.from('users').select('nickname, full_name, phone').eq('id', b.user_id).maybeSingle();
      customer = (u?.nickname || u?.full_name || '-') + (u?.phone ? ' · ' + u.phone : '');
    }
  } catch (_) { /* best effort */ }

  const flex = {
    type: 'flex',
    altText: `จองใหม่: ${tripName} (${fmtBaht(Number(b.total_price))})`,
    contents: {
      type: 'bubble',
      header: {
        type: 'box', layout: 'vertical', backgroundColor: '#E2672B', paddingAll: '14px',
        contents: [{ type: 'text', text: '🏔️ มีการจองใหม่', color: '#ffffff', weight: 'bold', size: 'md' }],
      },
      body: {
        type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '16px',
        contents: [
          { type: 'text', text: tripName, weight: 'bold', size: 'lg', wrap: true },
          { type: 'box', layout: 'baseline', spacing: 'sm', contents: [
            { type: 'text', text: 'เลขจอง', color: '#8B7E6B', size: 'sm', flex: 2 },
            { type: 'text', text: String(b.booking_ref || '-'), size: 'sm', flex: 5, wrap: true } ] },
          { type: 'box', layout: 'baseline', spacing: 'sm', contents: [
            { type: 'text', text: 'ลูกค้า', color: '#8B7E6B', size: 'sm', flex: 2 },
            { type: 'text', text: customer, size: 'sm', flex: 5, wrap: true } ] },
          { type: 'box', layout: 'baseline', spacing: 'sm', contents: [
            { type: 'text', text: 'ที่นั่ง', color: '#8B7E6B', size: 'sm', flex: 2 },
            { type: 'text', text: String(b.seats || 1) + ' ที่', size: 'sm', flex: 5 } ] },
          { type: 'box', layout: 'baseline', spacing: 'sm', contents: [
            { type: 'text', text: 'ยอดรวม', color: '#8B7E6B', size: 'sm', flex: 2 },
            { type: 'text', text: fmtBaht(Number(b.total_price)), size: 'sm', flex: 5, weight: 'bold', color: '#E2672B' } ] },
          ...(startDate ? [{ type: 'box', layout: 'baseline', spacing: 'sm', contents: [
            { type: 'text', text: 'เดินทาง', color: '#8B7E6B', size: 'sm', flex: 2 },
            { type: 'text', text: startDate, size: 'sm', flex: 5 } ] }] : []),
        ],
      },
      footer: {
        type: 'box', layout: 'horizontal', spacing: 'sm', paddingAll: '12px',
        contents: [
          { type: 'button', style: 'primary', color: '#2E7D32', height: 'sm',
            action: { type: 'postback', label: '✅ อนุมัติ', data: `action=approve&bookingId=${bookingId}`,
              displayText: `อนุมัติการจอง ${b.booking_ref || bookingId}` } },
          { type: 'button', style: 'primary', color: '#C0392B', height: 'sm',
            action: { type: 'postback', label: '❌ ปฏิเสธ', data: `action=reject&bookingId=${bookingId}`,
              displayText: `ปฏิเสธการจอง ${b.booking_ref || bookingId}` } },
        ],
      },
    },
  };

  const res = await fetch(LINE_PUSH, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + Deno.env.get('TEAM_LINE_CHANNEL_TOKEN') },
    body: JSON.stringify({ to: Deno.env.get('TEAM_LINE_GROUP_ID'), messages: [flex] }),
  });
  if (!res.ok) {
    const t = await res.text();
    console.error('LINE push failed', res.status, t);
    return j({ ok: false, line_status: res.status, detail: t }, 200); // 200 กัน webhook retry ถล่ม
  }
  return j({ ok: true, bookingId });
});
