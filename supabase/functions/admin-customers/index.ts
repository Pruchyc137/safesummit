// SafeSummit — Secure Admin API (Supabase Edge Function)
// จัดการรายชื่อ/อนุมัติลูกค้า โดยใช้ service_role key ฝั่ง server
// ป้องกันไม่ให้ข้อมูลลูกค้า (เลขบัตร ปชช. ฯลฯ) หลุดออกทาง publishable key
//
// Deploy:
//   supabase link --project-ref wucrvtgpjqjxxqarzcpv
//   supabase secrets set ADMIN_API_KEY=<ตั้งรหัสลับยาวๆ ของคุณเอง>
//   supabase functions deploy admin-customers --no-verify-jwt
//
// เรียกจาก client ด้วย header:  x-admin-key: <ADMIN_API_KEY>

import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  // ── ตรวจรหัสลับของ admin ──
  const adminKey = req.headers.get('x-admin-key');
  if (!adminKey || adminKey !== Deno.env.get('ADMIN_API_KEY')) {
    return json({ error: 'unauthorized' }, 401);
  }

  // ── client ฝั่ง server ใช้ service_role (ข้าม RLS ได้) ──
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let payload: { action?: string; id?: string; paid_amount?: number; note?: string; trip_id?: string; trip?: Record<string, unknown>; org?: Record<string, unknown> };
  try { payload = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
  const { action, id } = payload;

  try {
    if (action === 'list') {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('role', 'customer')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return json({ customers: data });
    }

    if (action === 'approve' || action === 'suspend') {
      if (!id) return json({ error: 'missing id' }, 400);
      const status = action === 'approve' ? 'approved' : 'suspended';
      const { error } = await supabase.from('users').update({ status }).eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, status });
    }

    // ===== PHASE 5: ตรวจสลิป/อนุมัติการชำระเงิน =====
    if (action === 'list_pending_payments') {
      const { data, error } = await supabase
        .from('bookings')
        .select('id, booking_ref, seats, total_price, declared_amount, paid_amount, slip_url, slip_uploaded_at, note, trip_id, users ( full_name, nickname, line_id, phone ), trips ( name_th )')
        .eq('pay_status', 'pending_review')
        .order('slip_uploaded_at', { ascending: true });
      if (error) throw error;
      return json({ bookings: data });
    }

    // รายการชำระเงินทั้งหมด (รวมที่อนุมัติ/ปฏิเสธแล้ว) — ดูย้อนหลังได้
    if (action === 'list_all_payments') {
      const { data, error } = await supabase
        .from('bookings')
        .select('id, booking_ref, seats, seat_numbers, total_price, declared_amount, paid_amount, slip_url, slip_uploaded_at, pay_status, verified_at, admin_note, note, trip_id, users ( full_name, nickname, line_id, phone ), trips ( name_th, start_date )')
        .not('slip_url', 'is', null)
        .order('slip_uploaded_at', { ascending: false });
      if (error) throw error;
      return json({ bookings: data });
    }

    // แผนผังที่นั่งรถตู้ต่อทริป: ผู้จองที่ยืนยัน/รอตรวจ + เลขที่นั่ง + สลิป
    if (action === 'trip_seatmap') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { data: trip, error: te } = await supabase
        .from('trips').select('name_th, start_date, capacity, booked_count').eq('id', id).maybeSingle();
      if (te) throw te;
      const { data: bk, error: be } = await supabase
        .from('bookings')
        .select('id, booking_ref, seats, seat_numbers, pay_status, slip_url, total_price, paid_amount, users ( full_name, nickname, phone )')
        .eq('trip_id', id)
        .not('pay_status', 'in', '(rejected)')
        .order('booked_at', { ascending: true });
      if (be) throw be;
      return json({ trip, bookings: bk });
    }

    if (action === 'slip_signed_url') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { data: b, error: be } = await supabase.from('bookings').select('slip_url').eq('id', id).maybeSingle();
      if (be) throw be;
      if (!b?.slip_url) return json({ error: 'no slip' }, 404);
      const { data: signed, error: se } = await supabase.storage.from('slips').createSignedUrl(b.slip_url, 3600);
      if (se) throw se;
      return json({ url: signed.signedUrl });
    }

    if (action === 'approve_payment') {
      if (!id) return json({ error: 'missing id' }, 400);
      const paid = Number(payload.paid_amount);
      if (!(paid > 0)) return json({ error: 'paid_amount must be > 0' }, 400);
      const { data: b, error: be } = await supabase.from('bookings').select('total_price, trip_id').eq('id', id).maybeSingle();
      if (be) throw be;
      if (!b) return json({ error: 'booking not found' }, 404);
      const total = Number(b.total_price) || 0;
      const status = paid >= total ? 'verified' : 'partial';
      const { error: ue } = await supabase.from('bookings').update({
        paid_amount: paid,
        pay_status: status,
        verified_at: new Date().toISOString(),
        admin_note: payload.note || null,
      }).eq('id', id);
      if (ue) throw ue;
      await supabase.from('payment_reviews').insert({
        booking_id: id, action: status === 'verified' ? 'approve' : 'partial',
        paid_amount: paid, note: payload.note || null,
      });
      // เช็คเงื่อนไข >=3 คน → ตั้ง group_status='ready'
      const { count } = await supabase.from('bookings')
        .select('id', { count: 'exact', head: true })
        .eq('trip_id', b.trip_id).in('pay_status', ['verified', 'partial']);
      if ((count || 0) >= 3) {
        await supabase.from('trips').update({ group_status: 'ready' })
          .eq('id', b.trip_id).eq('group_status', 'none');
      }
      return json({ ok: true, id, pay_status: status, confirmed_count: count || 0 });
    }

    if (action === 'reject_payment') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { error: ue } = await supabase.from('bookings').update({
        pay_status: 'rejected', admin_note: payload.note || null,
      }).eq('id', id);
      if (ue) throw ue;
      await supabase.from('payment_reviews').insert({
        booking_id: id, action: 'reject', paid_amount: null, note: payload.note || null,
      });
      return json({ ok: true, id, pay_status: 'rejected' });
    }

    // ===== ADMIN: ดูแลรีวิว (รายการทั้งหมด + ซ่อน/แสดง + ลบ) =====
    if (action === 'list_reviews') {
      const { data: revs, error } = await supabase
        .from('reviews')
        .select('id, rating, comment, hidden, created_at, user_id, trip_id, trips ( name_th )')
        .order('created_at', { ascending: false });
      if (error) throw error;
      const out = [];
      for (const r of revs || []) {
        let reviewer = 'นักเดินป่า';
        if (r.user_id) {
          const { data: u } = await supabase.from('users').select('nickname, full_name').eq('id', r.user_id).maybeSingle();
          reviewer = (u?.nickname && u.nickname.trim()) || (u?.full_name && u.full_name.trim()) || 'นักเดินป่า';
        }
        out.push({
          id: r.id, rating: r.rating, comment: r.comment, hidden: !!r.hidden,
          created_at: r.created_at, reviewer, trip_name: r.trips?.name_th || '',
        });
      }
      return json({ reviews: out });
    }

    if (action === 'set_review_hidden') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { error } = await supabase.from('reviews').update({ hidden: !!payload.hidden }).eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, hidden: !!payload.hidden });
    }

    if (action === 'delete_review') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { error } = await supabase.from('reviews').delete().eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, deleted: true });
    }

    // ===== ADMIN: รายชื่อผู้จัด + ข้อมูลติดต่อจริง (ชื่อ/อีเมล/เบอร์ อยู่ใน auth ไม่ใช่ตาราง organizers) =====
    if (action === 'list_organizers') {
      const { data: orgs, error } = await supabase
        .from('organizers').select('*').order('created_at', { ascending: false });
      if (error) throw error;
      const out = [];
      for (const o of orgs || []) {
        let full_name = null, email = null, phone = null;
        if (o.user_id) {
          try {
            const { data: au } = await supabase.auth.admin.getUserById(o.user_id);
            const u = au?.user;
            if (u) {
              email = u.email ?? null;
              full_name = (u.user_metadata?.full_name as string) ?? null;
              phone = (u.user_metadata?.phone as string) ?? u.phone ?? null;
            }
          } catch (_) { /* ผู้ใช้ถูกลบ/ไม่พบ → ปล่อยว่าง */ }
        }
        out.push({ ...o, full_name, email, phone });
      }
      return json({ organizers: out });
    }

    // ===== ADMIN: อนุมัติ/ระงับ/ให้ badge ผู้จัด (หลังล็อกดาวน์ anon เขียน organizers ไม่ได้แล้ว) =====
    if (action === 'update_organizer') {
      if (!id) return json({ error: 'missing id' }, 400);
      const ALLOWED = [
        'status', 'badge_tier', 'note', 'approved_at', 'suspended_at',
        'org_name', 'province', 'exp_years', 'bio',
      ];
      const src = payload.org || {};
      const patch: Record<string, unknown> = {};
      for (const k of ALLOWED) if (k in src) patch[k] = src[k];
      if (!Object.keys(patch).length) return json({ error: 'no allowed fields' }, 400);
      const { error } = await supabase.from('organizers').update(patch).eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, patch });
    }

    // ===== ADMIN: แก้ไข/อนุมัติทริป (RLS บล็อก anon → ต้องผ่าน service_role ที่นี่) =====
    if (action === 'update_trip') {
      if (!id) return json({ error: 'missing id' }, 400);
      const ALLOWED = [
        'status', 'note', 'name_th', 'name_en', 'province', 'start_date', 'capacity',
        'booked_count', 'price_per_person', 'trip_type', 'image_url', 'images',
        'description', 'difficulty',
      ];
      const src = payload.trip || {};
      const patch: Record<string, unknown> = {};
      for (const k of ALLOWED) if (k in src) patch[k] = src[k];
      if (!Object.keys(patch).length) return json({ error: 'no allowed fields' }, 400);
      // ถ้ามีการเปลี่ยน "รูปทริป" → ดึงค่าเดิมไว้ก่อนเพื่อบันทึก log
      let oldImg: string | null = null;
      if ('image_url' in patch) {
        const { data: prev } = await supabase.from('trips').select('image_url').eq('id', id).maybeSingle();
        oldImg = (prev?.image_url as string) ?? null;
      }
      const { error } = await supabase.from('trips').update(patch).eq('id', id);
      if (error) throw error;
      // บันทึกประวัติเปลี่ยนรูป (เฉพาะเมื่อ url เปลี่ยนจริง) — best-effort ไม่ให้ล้มทั้ง request
      if ('image_url' in patch && (patch.image_url ?? null) !== oldImg) {
        try {
          await supabase.from('trip_image_log').insert({
            trip_id: id, old_url: oldImg, new_url: (patch.image_url as string) ?? null, source: 'admin',
          });
        } catch (_) { /* ตาราง log ยังไม่ถูกสร้าง (ยังไม่รัน phase18) → ข้าม */ }
      }
      return json({ ok: true, id, patch });
    }

    // ประวัติการเปลี่ยนรูปของทริปหนึ่ง (ให้ Admin ดูย้อนหลัง)
    if (action === 'trip_image_log') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { data, error } = await supabase.from('trip_image_log')
        .select('old_url, new_url, source, changed_at').eq('trip_id', id)
        .order('changed_at', { ascending: false }).limit(20);
      if (error) throw error;
      return json({ log: data });
    }

    // ===== PHASE 6: กลุ่ม LINE =====
    if (action === 'list_group_ready') {
      // ทริปที่มีผู้ยืนยัน >=3 พร้อม confirmed_count (สำหรับ badge/ปุ่มสร้างกลุ่ม)
      const { data: trips, error: te } = await supabase
        .from('trips').select('id, name_th, group_status, group_created_at, group_note')
        .in('group_status', ['ready', 'created']).order('start_date', { ascending: true });
      if (te) throw te;
      const out = [];
      for (const t of trips || []) {
        const { count } = await supabase.from('bookings')
          .select('id', { count: 'exact', head: true })
          .eq('trip_id', t.id).in('pay_status', ['verified', 'partial']);
        out.push({ ...t, confirmed_count: count || 0 });
      }
      return json({ trips: out });
    }

    if (action === 'trip_confirmed_members') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { data, error } = await supabase.from('bookings')
        .select('id, booking_ref, seats, pay_status, users ( full_name, nickname, line_id, phone )')
        .eq('trip_id', id).in('pay_status', ['verified', 'partial'])
        .order('booked_at', { ascending: true });
      if (error) throw error;
      return json({ members: data });
    }

    if (action === 'mark_group_created') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { error } = await supabase.from('trips').update({
        group_status: 'created', group_created_at: new Date().toISOString(),
        group_note: payload.note || null,
      }).eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, group_status: 'created' });
    }

    // ===== PHASE 16: คิวคืนเงิน (ลูกค้ายกเลิก → ส่งคำขอ → Admin โอนจริง → กดยืนยันที่นี่) =====
    if (action === 'list_pending_refunds') {
      const { data, error } = await supabase
        .from('bookings')
        .select('id, booking_ref, seats, total_price, cancelled_at, cancel_reason, refund_pct, refund_amount, refund_status, trip_id, users ( full_name, nickname, phone, line_id ), trips ( name_th, start_date )')
        .eq('refund_status', 'pending')
        .order('cancelled_at', { ascending: true });
      if (error) throw error;
      return json({ bookings: data });
    }

    if (action === 'mark_refund_paid') {
      if (!id) return json({ error: 'missing id' }, 400);
      const { data: b, error: be } = await supabase.from('bookings').select('refund_amount').eq('id', id).maybeSingle();
      if (be) throw be;
      if (!b) return json({ error: 'booking not found' }, 404);
      const { error: ue } = await supabase.from('bookings').update({
        refund_status: 'paid',
        refund_paid_at: new Date().toISOString(),
        refund_note: payload.note || null,
      }).eq('id', id);
      if (ue) throw ue;
      await supabase.from('refund_reviews').insert({
        booking_id: id, action: 'mark_paid', refund_amount: b.refund_amount, note: payload.note || null,
      });
      return json({ ok: true, id, refund_status: 'paid' });
    }

    return json({ error: 'unknown action' }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
