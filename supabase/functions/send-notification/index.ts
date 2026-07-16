// SafeSummit — Booking/Payment Email Notifications (Supabase Edge Function)
// เรียกอัตโนมัติจาก Supabase Database Webhook เมื่อ bookings ถูก insert/update
// ส่งอีเมลแจ้งลูกค้าผ่าน Resend (https://resend.com)
//
// Deploy:
//   supabase functions deploy send-notification --no-verify-jwt
//   supabase secrets set RESEND_API_KEY=<API key จาก Resend>
//   supabase secrets set RESEND_FROM="SafeSummit <onboarding@resend.dev>"   (หรือโดเมนที่ verify แล้ว)
//   supabase secrets set WEBHOOK_SECRET=<ตั้งรหัสลับยาวๆ ของคุณเอง>
//
// ตั้งค่าใน Supabase Dashboard → Database → Webhooks → Create webhook:
//   Table: bookings · Events: Insert, Update
//   Type: HTTP Request → URL: https://<project>.supabase.co/functions/v1/send-notification
//   HTTP Headers: เพิ่ม header ชื่อ x-webhook-secret ค่า = WEBHOOK_SECRET ที่ตั้งไว้ข้างบน

import { createClient } from 'jsr:@supabase/supabase-js@2';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

async function sendEmail(to: string, subject: string, html: string) {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('RESEND_FROM') || 'SafeSummit <onboarding@resend.dev>';
  if (!apiKey || !to) return { skipped: true };
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  if (!res.ok) console.error('resend error', res.status, await res.text());
  return { ok: res.ok };
}

const fmtMoney = (n: number) => '฿' + Number(n || 0).toLocaleString('th-TH');
const fmtDate = (d: string | null) =>
  d ? new Date(d + 'T00:00:00').toLocaleDateString('th-TH', { day: 'numeric', month: 'long', year: 'numeric' }) : '–';

function wrap(title: string, bodyHtml: string) {
  return `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;">
    <h2 style="color:#2B2118;">${title}</h2>
    ${bodyHtml}
    <p style="color:#8B7E6B;font-size:12.5px;margin-top:28px;">SafeSummit — แพลตฟอร์มจองทริปเดินป่า</p>
  </div>`;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const secret = req.headers.get('x-webhook-secret');
  if (!secret || secret !== Deno.env.get('WEBHOOK_SECRET')) return json({ error: 'unauthorized' }, 401);

  let payload: { type?: string; table?: string; record?: any; old_record?: any };
  try { payload = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
  if (payload.table !== 'bookings' || !payload.record) return json({ ok: true, skipped: true });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const b = payload.record;
  const old = payload.old_record || {};

  try {
    const { data: user } = await supabase.from('users').select('email, full_name, nickname').eq('id', b.user_id).maybeSingle();
    const { data: trip } = await supabase.from('trips').select('name_th, start_date').eq('id', b.trip_id).maybeSingle();
    const email = user?.email;
    const name = user?.nickname || user?.full_name || 'นักเดินป่า';
    const tripName = trip?.name_th || 'ทริป';
    if (!email) return json({ ok: true, skipped: 'no email' });

    // ── INSERT: จองใหม่ ──
    if (payload.type === 'INSERT') {
      await sendEmail(email, `จองทริป "${tripName}" สำเร็จ — SafeSummit`, wrap('จองทริปสำเร็จ ✓', `
        <p>สวัสดีคุณ${name},</p>
        <p>เราได้รับการจองทริป <b>${tripName}</b> ของคุณแล้ว (เลขที่จอง <b>${b.booking_ref || '-'}</b>)</p>
        <p>วันเดินทาง: ${fmtDate(trip?.start_date)}<br>ยอดที่ต้องชำระ: ${fmtMoney(b.total_price)}</p>
        <p>กรุณาชำระเงินและอัปโหลดสลิปในหน้า "ทริปของฉัน" เพื่อยืนยันที่นั่ง</p>
      `));
      return json({ ok: true, sent: 'booking_created' });
    }

    // ── UPDATE: เช็คว่าฟิลด์ไหนเปลี่ยน ──
    if (payload.type === 'UPDATE') {
      if (b.pay_status !== old.pay_status) {
        if (b.pay_status === 'verified') {
          await sendEmail(email, `ชำระเงินสำเร็จ — ${tripName}`, wrap('ชำระเงินครบแล้ว ✓', `
            <p>สวัสดีคุณ${name}, การชำระเงินสำหรับทริป <b>${tripName}</b> ได้รับการยืนยันครบถ้วนแล้ว ที่นั่งของคุณยืนยันแล้ว 🎉</p>
          `));
          return json({ ok: true, sent: 'payment_verified' });
        }
        if (b.pay_status === 'partial') {
          await sendEmail(email, `ได้รับมัดจำแล้ว — ${tripName}`, wrap('ได้รับมัดจำแล้ว', `
            <p>สวัสดีคุณ${name}, เราได้รับเงินมัดจำสำหรับทริป <b>${tripName}</b> แล้ว จำนวน ${fmtMoney(b.paid_amount)}</p>
            <p>กรุณาชำระส่วนที่เหลือก่อนวันเดินทาง</p>
          `));
          return json({ ok: true, sent: 'payment_partial' });
        }
        if (b.pay_status === 'rejected') {
          await sendEmail(email, `การชำระเงินถูกปฏิเสธ — ${tripName}`, wrap('การชำระเงินถูกปฏิเสธ', `
            <p>สวัสดีคุณ${name}, สลิปการชำระเงินของทริป <b>${tripName}</b> ไม่ผ่านการตรวจสอบ</p>
            ${b.admin_note ? `<p>เหตุผล: ${b.admin_note}</p>` : ''}
            <p>กรุณาอัปโหลดสลิปใหม่ในหน้า "ทริปของฉัน"</p>
          `));
          return json({ ok: true, sent: 'payment_rejected' });
        }
      }
      if (b.refund_status === 'paid' && old.refund_status !== 'paid') {
        await sendEmail(email, `คืนเงินเรียบร้อยแล้ว — ${tripName}`, wrap('คืนเงินเรียบร้อยแล้ว ✓', `
          <p>สวัสดีคุณ${name}, เราได้โอนเงินคืน ${fmtMoney(b.refund_amount)} สำหรับการยกเลิกทริป <b>${tripName}</b> เรียบร้อยแล้ว</p>
        `));
        return json({ ok: true, sent: 'refund_paid' });
      }
    }

    return json({ ok: true, skipped: 'no matching change' });
  } catch (e) {
    console.error('send-notification error', e);
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
