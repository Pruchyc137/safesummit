-- ============================================================
-- SafeSummit — Phase 16: ติดตามการยกเลิก/คืนเงินจริง
-- รันใน Supabase Dashboard → SQL Editor → Run
-- (ปลอดภัยต่อการรันซ้ำ ใช้ IF NOT EXISTS ทั้งหมด)
--
-- ก่อนหน้านี้ my-trips.html โชว์ "คืนเงินแล้ว" ทันทีตอนลูกค้ากดยกเลิก
-- ทั้งที่ไม่มีการโอนเงินจริงเกิดขึ้น และไม่มีที่ไหนบันทึกไว้ให้ Admin เห็น
-- Phase นี้เพิ่มคอลัมน์ให้ยกเลิก = สร้างคำขอคืนเงินที่ Admin ต้องมาอนุมัติ/โอนเอง
-- ============================================================

alter table bookings add column if not exists cancelled_at    timestamptz;
alter table bookings add column if not exists cancel_reason   text;
alter table bookings add column if not exists refund_pct      int;
alter table bookings add column if not exists refund_amount   numeric;
alter table bookings add column if not exists refund_status   text not null default 'none';  -- none | pending | paid
alter table bookings add column if not exists refund_paid_at  timestamptz;
alter table bookings add column if not exists refund_note     text;  -- บันทึกของ Admin ตอนโอนคืน (เช่น เลขอ้างอิงการโอน)

-- log การดำเนินการคืนเงินของ Admin (ตรวจย้อนหลังได้ เหมือน payment_reviews)
create table if not exists refund_reviews (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid references bookings(id) on delete cascade,
  action       text,          -- 'mark_paid'
  refund_amount numeric,
  note         text,
  created_at   timestamptz default now()
);
