-- ============================================================
-- SafeSummit — Phase 1: Schema สำหรับระบบจ่ายเงิน + ตรวจสลิป + กลุ่ม LINE
-- รันใน Supabase Dashboard → SQL Editor → Run
-- (ปลอดภัยต่อการรันซ้ำ ใช้ IF NOT EXISTS ทั้งหมด)
-- ============================================================

-- 1.1 QR พร้อมเพย์ของผู้จัด
alter table organizers add column if not exists payment_qr_url text;

-- 1.2 ทริป: QR เฉพาะทริป (ถ้าไม่ใส่ ใช้ของผู้จัด) + สถานะกลุ่ม LINE
alter table trips add column if not exists payment_qr_url   text;
alter table trips add column if not exists group_status     text not null default 'none';  -- none | ready | created
alter table trips add column if not exists group_created_at timestamptz;
alter table trips add column if not exists group_note       text;   -- ลิงก์/โน้ตกลุ่ม LINE

-- 1.3 ลูกค้า: LINE ID
alter table users add column if not exists line_id text;

-- 1.4 การจอง: ข้อมูลการจ่าย/สลิป/การตรวจ
alter table bookings add column if not exists total_price      numeric;   -- ยอดที่ต้องจ่ายทั้งหมด
alter table bookings add column if not exists declared_amount  numeric;   -- ลูกค้าแจ้งว่าจ่ายเท่าไหร่
alter table bookings add column if not exists paid_amount      numeric;   -- Admin ยืนยันจริงเท่าไหร่ (source of truth)
alter table bookings add column if not exists slip_url         text;      -- path สลิปใน bucket 'slips'
alter table bookings add column if not exists slip_uploaded_at timestamptz;
alter table bookings add column if not exists verified_by      uuid references auth.users(id);
alter table bookings add column if not exists verified_at      timestamptz;
alter table bookings add column if not exists admin_note       text;
-- หมายเหตุ: bookings.pay_status มีอยู่แล้ว (unpaid). ค่าใหม่ที่ใช้: pending_review | verified | partial | rejected

-- 1.5 log การตรวจของ Admin (ตรวจย้อนหลัง)
create table if not exists payment_reviews (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid references bookings(id) on delete cascade,
  admin_id     uuid,          -- อาจเป็น null เพราะ Admin ใช้ระบบ local (ตรวจผ่าน Edge Function)
  action       text,          -- 'approve' | 'partial' | 'reject'
  paid_amount  numeric,
  note         text,
  created_at   timestamptz default now()
);

-- 1.6 View: นับคนที่ยืนยันแล้วต่อทริป (ใช้เช็คเงื่อนไข >= 3)
create or replace view trip_confirmed as
select t.id as trip_id, t.name_th,
       count(b.*) filter (where b.pay_status in ('verified','partial')) as confirmed_count
from trips t
left join bookings b on b.trip_id = t.id
group by t.id, t.name_th;

-- ============================================================
-- Storage buckets — สร้างในหน้า Supabase → Storage (ไม่ใช่ SQL):
--   • payment-qr : Public bucket (ลูกค้าต้องเห็น QR)
--   • slips      : Private bucket (สลิป = ข้อมูลส่วนตัว, เปิดผ่าน signed URL เท่านั้น)
-- ============================================================
