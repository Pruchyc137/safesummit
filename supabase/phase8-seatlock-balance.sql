-- ============================================================
-- SafeSummit — Phase 8: กันจองที่นั่งซ้ำ + จ่ายส่วนที่เหลือ + ปิดช่องลูกค้ายืนยันเงินเอง
-- รันใน Supabase Dashboard → SQL Editor → Run (หลัง deploy โค้ดเว็บ)
-- ============================================================

-- ---------- 1) ที่นั่งที่ถูกจองไปแล้วของทริป (ไม่เผย PII) ----------
-- ใช้ให้หน้าจองรู้ว่าที่นั่งไหนไม่ว่าง (ลูกค้าอ่าน bookings ของคนอื่นไม่ได้)
create or replace function public.trip_taken_seats(p_trip_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(s), '{}')
  from public.bookings b, unnest(b.seat_numbers) s
  where b.trip_id = p_trip_id
    and b.pay_status <> 'rejected'
    and b.status <> 'cancelled'
$$;
revoke all on function public.trip_taken_seats(uuid) from public;
grant execute on function public.trip_taken_seats(uuid) to anon, authenticated;

-- ---------- 2) ลูกค้าส่งสลิป/แจ้งยอด (ตั้งได้แค่ 'pending_review' ห้ามตั้ง verified เอง) ----------
create or replace function public.submit_booking_payment(
  p_booking_id uuid, p_declared numeric, p_slip_url text, p_is_balance boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bookings
     set slip_url         = p_slip_url,
         slip_uploaded_at = now(),
         declared_amount  = p_declared,
         pay_status       = 'pending_review',
         admin_note       = case when p_is_balance then '[จ่ายส่วนที่เหลือ]' else null end
   where id = p_booking_id
     and user_id = auth.uid()
     and pay_status in ('unpaid','rejected','partial','pending_review');
  if not found then
    raise exception 'ไม่พบการจอง หรือไม่มีสิทธิ์แก้ไข';
  end if;
end $$;
revoke all on function public.submit_booking_payment(uuid,numeric,text,boolean) from public, anon;
grant execute on function public.submit_booking_payment(uuid,numeric,text,boolean) to authenticated;

-- ---------- 3) ปิดช่องลูกค้าตั้ง pay_status/paid_amount เอง ----------
-- ลูกค้ายังแก้แถวตัวเองได้ (RLS เดิม) แต่ "เขียนคอลัมน์เงิน/ยืนยัน" ไม่ได้แล้ว
-- (สถานะเปลี่ยนผ่าน RPC ข้อ 2 หรือ Admin ผ่าน Edge Function เท่านั้น)
revoke update on public.bookings from authenticated;
grant update (
  status, note, seat_numbers, slip_url, slip_uploaded_at, declared_amount
) on public.bookings to authenticated;
-- คอลัมน์ที่ "ไม่" ให้ลูกค้าเขียน: pay_status, paid_amount, verified_by, verified_at, admin_note, total_price, user_id, trip_id
-- insert/select/delete ของ bookings ไม่กระทบ (ยังทำงานตาม RLS เดิม)
