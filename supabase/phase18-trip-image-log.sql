-- ============================================================
-- SafeSummit — Phase 18: บันทึกประวัติการเปลี่ยนรูปทริปโดย Admin
--   เก็บ log ทุกครั้งที่รูปทริป (image_url) ถูกเปลี่ยนผ่าน Admin (Edge Function)
--   เพื่อตรวจย้อนหลังได้ เผื่อ Admin เปลี่ยนรูปทริปของผู้จัดโดยผู้จัดไม่ทราบ
--
-- หมายเหตุ: ตอนนี้ Admin ใช้ ADMIN_API_KEY ตัวเดียวร่วมกัน (ไม่มี id แยกรายคน)
--           log จึงบันทึก source='admin' + เวลา + url เก่า→ใหม่ (ระบุตัวบุคคลไม่ได้)
--           ถ้าต้องการแยกรายคนในอนาคต ต้องเปลี่ยนไปใช้ Supabase Auth ต่อ admin แต่ละคน
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

create table if not exists public.trip_image_log (
  id          bigint generated always as identity primary key,
  trip_id     uuid not null,
  old_url     text,
  new_url     text,
  source      text default 'admin',
  changed_at  timestamptz default now()
);

create index if not exists trip_image_log_trip_idx on public.trip_image_log(trip_id, changed_at desc);

-- เขียนผ่าน service_role (Edge Function) เท่านั้น — เปิด RLS ไม่ให้ client แตะ
alter table public.trip_image_log enable row level security;
-- ไม่สร้าง policy = client (anon/authenticated) อ่าน/เขียนไม่ได้ · service_role ข้าม RLS อยู่แล้ว
