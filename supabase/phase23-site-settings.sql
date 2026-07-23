-- ============================================================
-- SafeSummit — Phase 23: ตั้งค่าเว็บที่ Admin แก้ได้ (เริ่มจากรูป Hero หน้าแรก)
--   ใช้ Supabase Auth admin (phase22) เป็นด่าน → ไม่ต้องแตะ Edge Function
--   รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

create table if not exists public.site_settings (
  key        text primary key,
  value      text,
  updated_at timestamptz default now(),
  updated_by text
);

-- ทุกคนอ่านได้ (หน้าเว็บต้องใช้) · เขียนได้ผ่าน RPC เท่านั้น
alter table public.site_settings enable row level security;
drop policy if exists "site_settings public read" on public.site_settings;
create policy "site_settings public read" on public.site_settings for select using (true);

-- ค่าเริ่มต้นของรูป Hero (ถ้ายังไม่มี)
insert into public.site_settings (key, value) values ('hero_image', 'images/Hero/hero1.jpg')
on conflict (key) do nothing;

-- Admin (Supabase Auth ที่อยู่ในตาราง admins) เท่านั้นที่เขียนได้
create or replace function public.set_site_setting(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'ต้องเป็นผู้ดูแลระบบเท่านั้น';
  end if;
  insert into public.site_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(),
          (select coalesce(a.name, '') from public.admins a where a.user_id = auth.uid()))
  on conflict (key) do update
    set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
end $$;
revoke all on function public.set_site_setting(text, text) from public, anon;
grant execute on function public.set_site_setting(text, text) to authenticated;
