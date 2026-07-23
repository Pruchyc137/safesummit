-- ============================================================
-- SafeSummit — Phase 22: Admin เป็น Supabase Auth รายคน (แทน key ตัวเดียว)
--   เพื่อให้ระบุได้ว่า "ใคร" ทำอะไร (log/audit) แทนที่จะเป็น admin นิรนามที่ใช้ key ร่วมกัน
--
--   ออกแบบ dual-mode: Edge Function รับได้ทั้ง
--     (ก) ADMIN_API_KEY เดิม (x-admin-key)  — ยังใช้ได้ ไม่ให้ระบบพัง
--     (ข) admin JWT ใหม่ (ผู้ใช้ Supabase Auth ที่อยู่ในตาราง admins)
--
--   วิธีเพิ่ม admin รายคน:
--     1) สร้างบัญชีให้เขา (Supabase Dashboard → Authentication → Add user, หรือให้สมัครผ่านเว็บ)
--     2) เอา user id มา insert ลง admins (ดูตัวอย่างท้ายไฟล์)
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

create table if not exists public.admins (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  name     text,
  added_at timestamptz default now()
);

alter table public.admins enable row level security;
-- ไม่มี policy = client (anon/authenticated) อ่าน/เขียนไม่ได้ · service_role (Edge Function) ข้าม RLS

-- helper: เช็คว่า uid เป็น admin ไหม (ให้หน้าเว็บใช้ตัดสินใจ UI ได้ — ไม่ใช่ประตูความปลอดภัย)
create or replace function public.is_admin(p_uid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.admins where user_id = p_uid) $$;
revoke all on function public.is_admin(uuid) from public, anon;
grant execute on function public.is_admin(uuid) to authenticated;

-- ให้ผู้ใช้เช็คสิทธิ์ "ตัวเอง" ได้ (ไม่ต้องส่ง uid — กันไปเช็คคนอื่น)
create or replace function public.am_i_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.admins where user_id = auth.uid()) $$;
revoke all on function public.am_i_admin() from public, anon;
grant execute on function public.am_i_admin() to authenticated;

-- ── เพิ่ม admin รายคน (แก้ค่าแล้วรัน) ─────────────────────────
-- วิธีหา user id: Supabase Dashboard → Authentication → Users → คลิกผู้ใช้ → คัดลอก UID
--
-- insert into public.admins (user_id, name) values
--   ('00000000-0000-0000-0000-000000000000', 'ปรัช')
-- on conflict (user_id) do update set name = excluded.name;
