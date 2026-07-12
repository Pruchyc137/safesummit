-- ============================================================
-- SafeSummit — Phase 12: สถานะที่นั่งแบบละเอียด (สำหรับหน้าลูกค้า)
-- คืน "เลขที่นั่ง + สถานะ" เพื่อให้ผังที่นั่งแยกได้ว่า
--   paid    = ชำระแล้ว (verified/partial)   → "จองแล้ว"
--   pending = ยังไม่ผ่านตรวจ (unpaid/pending_review) → "รอตรวจการชำระ"
-- คืนแค่ "สถานะการชำระ" ไม่คืนชื่อ/ข้อมูลส่วนตัวใคร (ปลอดภัยสำหรับ anon)
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

create or replace function public.trip_seat_status(p_trip_id uuid)
returns table(seat text, status text)
language sql
stable
security definer
set search_path = public
as $$
  select s,
         case when b.pay_status in ('verified','partial') then 'paid' else 'pending' end
  from public.bookings b, unnest(b.seat_numbers) s
  where b.trip_id = p_trip_id
    and b.pay_status <> 'rejected'
    and b.status <> 'cancelled'
$$;
revoke all on function public.trip_seat_status(uuid) from public;
grant execute on function public.trip_seat_status(uuid) to anon, authenticated;
