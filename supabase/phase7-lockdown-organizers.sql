-- ============================================================
-- SafeSummit — Phase 7: ปิดช่องโหว่ตาราง organizers
--
-- ปัญหาที่พบ (ทดสอบด้วย anon key ซึ่งฝังอยู่ใน source ของเว็บ):
--   1) anon อ่าน id_card / bank_account / license_number ของผู้จัดทุกคนได้
--   2) anon "เขียนทับ" ตาราง organizers ได้ → เปลี่ยน payment_qr_url ของผู้จัด
--      = เบนเงินลูกค้าเข้ากระเป๋าคนร้าย, ตั้ง status='approved' ให้ตัวเองได้
--
-- หลังรัน SQL นี้:
--   • anon อ่านได้เฉพาะคอลัมน์สาธารณะ (ชื่อทีม/ภาค/badge/QR/สถานะ) — พอสำหรับหน้าเว็บ
--   • anon เขียนอะไรไม่ได้เลย
--   • ผู้จัดแก้ได้เฉพาะ "แถวของตัวเอง" และเฉพาะคอลัมน์ที่ควรแก้ (ห้ามแตะ status/badge_tier)
--   • ผู้จัดอ่านข้อมูลเต็มของตัวเองผ่าน RPC get_my_organizer()
--   • Admin ยังเห็น/แก้ได้ครบทุกฟิลด์ผ่าน Edge Function (service_role ข้ามทั้งหมด)
--
-- ⚠️ ลำดับสำคัญ: redeploy Edge Function + deploy โค้ดเว็บ ให้เสร็จก่อน แล้วค่อยรันไฟล์นี้
-- รันใน Supabase Dashboard → SQL Editor → Run (รันซ้ำได้ปลอดภัย)
-- ============================================================

-- ---------- 1) RLS: ใครแตะแถวไหนได้ ----------
alter table public.organizers enable row level security;

-- อ่านได้ทุกแถว (คอลัมน์ที่อ่านได้ถูกคุมด้วย GRANT ข้อ 2 อีกชั้น)
drop policy if exists "org_public_read" on public.organizers;
create policy "org_public_read" on public.organizers
  for select to anon, authenticated using (true);

-- สมัครใหม่: ต้องเป็นแถวของตัวเอง และต้องเริ่มที่ pending/unverified เสมอ (กันอนุมัติตัวเองตอน insert)
drop policy if exists "org_owner_insert" on public.organizers;
create policy "org_owner_insert" on public.organizers
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and badge_tier = 'unverified'
  );

-- แก้ไข: เฉพาะแถวของตัวเอง (คอลัมน์ที่แก้ได้ถูกคุมด้วย GRANT ข้อ 2)
drop policy if exists "org_owner_update" on public.organizers;
create policy "org_owner_update" on public.organizers
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------- 2) GRANT ระดับคอลัมน์: ใครเห็น/เขียนคอลัมน์ไหน ----------
revoke select, insert, update, delete on public.organizers from anon;
revoke select, insert, update, delete on public.organizers from authenticated;

-- อ่าน: คอลัมน์สาธารณะเท่านั้น (ไม่มี id_card / bank_* / license_* / line_id)
grant select (
  id, user_id, org_name, province, exp_years, bio,
  status, badge_tier, payment_qr_url, reg_ref, note,
  created_at, approved_at, suspended_at
) on public.organizers to anon, authenticated;

-- เขียน: เฉพาะ authenticated (RLS บังคับให้เป็นแถวตัวเอง)
grant insert on public.organizers to authenticated;   -- ตอนสมัคร (RLS บังคับ pending/unverified)
grant update (
  org_name, province, exp_years, bio, line_id, facebook_url,
  id_card, id_card_file_url,
  license_type, license_number, license_expiry, license_file_url,
  bank_name, bank_account, bank_account_name,
  payment_qr_url
) on public.organizers to authenticated;
-- สังเกต: ไม่ให้ update บน status, badge_tier, note, approved_at, suspended_at, user_id

-- ---------- 3) RPC: ผู้จัดอ่านข้อมูลเต็ม "ของตัวเอง" ----------
create or replace function public.get_my_organizer()
returns setof public.organizers
language sql
security definer
set search_path = public
as $$
  select * from public.organizers where user_id = auth.uid()
$$;
revoke all on function public.get_my_organizer() from public, anon;
grant execute on function public.get_my_organizer() to authenticated;

-- ---------- 4) RPC: ผู้จัดส่งใบสมัครใหม่ (ตั้ง status=pending ได้เฉพาะทางนี้) ----------
create or replace function public.organizer_resubmit(msg text default null)
returns void
language sql
security definer
set search_path = public
as $$
  update public.organizers
     set status = 'pending',
         note   = case when msg is null or msg = '' then '[ส่งใหม่]' else '[ส่งใหม่] ' || msg end
   where user_id = auth.uid()
$$;
revoke all on function public.organizer_resubmit(text) from public, anon;
grant execute on function public.organizer_resubmit(text) to authenticated;

-- ---------- ตรวจผล ----------
-- select id_card from organizers limit 1;            -- ควร error: permission denied (เมื่อรันด้วย anon)
-- select org_name, badge_tier from organizers limit 1;  -- ควรได้
