-- ============================================================
-- SafeSummit — Phase 2: RLS + Storage policies สำหรับระบบจ่ายเงิน
-- รันหลัง Phase 1 และหลังสร้าง bucket 'payment-qr' (public) + 'slips' (private)
-- ปลอดภัยต่อการรันซ้ำ (drop policy if exists ก่อน create)
--
-- โครงจริง: bookings.user_id = ลูกค้า, trips.organizer_id = organizers.id,
--           organizers.user_id = auth.uid(), users.role = 'customer'
-- Admin ใช้ระบบ local (anon key) → ตรวจ/อนุมัติผ่าน Edge Function (service_role bypass RLS)
--           จึงไม่พึ่ง RLS 'admin' ที่นี่
-- ============================================================

-- ---------- bookings ----------
alter table bookings enable row level security;

drop policy if exists "cust_select_own_bookings" on bookings;
create policy "cust_select_own_bookings" on bookings
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "cust_update_own_bookings" on bookings;
create policy "cust_update_own_bookings" on bookings
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "cust_insert_own_bookings" on bookings;
create policy "cust_insert_own_bookings" on bookings
  for insert to authenticated with check (auth.uid() = user_id);

-- ผู้จัดเห็น booking ของทริปตัวเอง (join ผ่าน organizers.user_id)
drop policy if exists "org_read_own_trip_bookings" on bookings;
create policy "org_read_own_trip_bookings" on bookings
  for select to authenticated using (
    exists (select 1 from trips t
            join organizers o on o.id = t.organizer_id
            where t.id = bookings.trip_id and o.user_id = auth.uid())
  );

-- ---------- users (แก้ 406 เวลาไม่มี row + ให้จัดการโปรไฟล์ตัวเอง) ----------
alter table users enable row level security;

drop policy if exists "read_own_profile" on users;
create policy "read_own_profile" on users
  for select to authenticated using (auth.uid() = id);

drop policy if exists "insert_own_profile" on users;
create policy "insert_own_profile" on users
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists "update_own_profile" on users;
create policy "update_own_profile" on users
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- ผู้จัดอ่านชื่อ/line_id ของลูกค้าที่จองทริปตัวเอง (สำหรับ manifest + กลุ่ม LINE)
drop policy if exists "org_read_own_trip_customers" on users;
create policy "org_read_own_trip_customers" on users
  for select to authenticated using (
    exists (select 1 from bookings b
            join trips t     on t.id = b.trip_id
            join organizers o on o.id = t.organizer_id
            where b.user_id = users.id and o.user_id = auth.uid())
  );

-- ---------- Storage: payment-qr (public read; เขียนเฉพาะเจ้าของโฟลเดอร์) ----------
-- path convention: payment-qr/{auth.uid()}/qr.png
drop policy if exists "qr_public_read" on storage.objects;
create policy "qr_public_read" on storage.objects
  for select to public using (bucket_id = 'payment-qr');

drop policy if exists "qr_owner_write" on storage.objects;
create policy "qr_owner_write" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'payment-qr' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "qr_owner_update" on storage.objects;
create policy "qr_owner_update" on storage.objects
  for update to authenticated using (
    bucket_id = 'payment-qr' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- Storage: slips (private; เจ้าของอัป/อ่านได้เท่านั้น, Admin อ่านผ่าน service_role) ----------
-- path convention: slips/{auth.uid()}/{bookingId}.jpg
drop policy if exists "slip_owner_insert" on storage.objects;
create policy "slip_owner_insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "slip_owner_select" on storage.objects;
create policy "slip_owner_select" on storage.objects
  for select to authenticated using (
    bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "slip_owner_update" on storage.objects;
create policy "slip_owner_update" on storage.objects
  for update to authenticated using (
    bucket_id = 'slips' and (storage.foldername(name))[1] = auth.uid()::text
  );
