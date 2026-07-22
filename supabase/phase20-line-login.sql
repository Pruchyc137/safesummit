-- ============================================================
-- SafeSummit — Phase 20: LINE Login เก็บ line_uid ของลูกค้า
--   ปิด flow "แจ้งลูกค้ากลับ" ของระบบอนุมัติผ่าน LINE (phase19)
--   รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
--
-- ออกแบบความปลอดภัย:
--   • line_uid เขียนได้จาก Edge Function `line-login` เท่านั้น (service_role)
--     หลังตรวจ OAuth code กับ LINE + ยืนยัน JWT ของผู้ใช้แล้ว
--     → เว็บส่ง uid ปลอมมาเองไม่ได้
--   • ตอนสร้าง booking ระบบคัดลอก users.line_uid → bookings.customer_line_uid
--     ให้อัตโนมัติด้วย trigger (ไม่ผ่านฝั่ง client)
-- ============================================================

-- 1) เก็บ LINE uid ไว้ที่โปรไฟล์ผู้ใช้ (ผูกครั้งเดียว ใช้ได้ทุกการจอง)
alter table public.users add column if not exists line_uid text;
create index if not exists users_line_uid_idx on public.users(line_uid);

-- 2) กันไม่ให้ client เขียน line_uid เอง (เขียนได้เฉพาะ service_role)
revoke update (line_uid) on public.users from anon, authenticated;

-- 3) ตอน insert booking → คัดลอก line_uid จากโปรไฟล์ผู้ใช้มาให้อัตโนมัติ
create or replace function public.copy_line_uid_to_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_line_uid is null and new.user_id is not null then
    select u.line_uid into new.customer_line_uid from public.users u where u.id = new.user_id;
  end if;
  return new;
end $$;

drop trigger if exists trg_booking_line_uid on public.bookings;
create trigger trg_booking_line_uid
  before insert on public.bookings
  for each row execute function public.copy_line_uid_to_booking();

-- 4) เผื่อผู้ใช้ผูก LINE ทีหลัง — เติม uid ให้ booking เก่าที่ยังรออนุมัติ
--    (รันซ้ำได้ ปลอดภัย)
update public.bookings b
   set customer_line_uid = u.line_uid
  from public.users u
 where b.user_id = u.id
   and b.customer_line_uid is null
   and u.line_uid is not null
   and coalesce(b.approval_status,'pending') = 'pending';
