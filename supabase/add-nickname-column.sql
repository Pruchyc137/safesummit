-- SafeSummit — เพิ่มช่อง "ชื่อเล่น" ให้ลูกค้า
-- ใช้แสดงในแผนผังที่นั่ง/รายชื่อผู้ร่วมทริป (ฐานข้อมูลยังเก็บชื่อจริง full_name ไว้ตามเดิม)
--
-- วิธีรัน: Supabase Dashboard → SQL Editor → วาง → Run

alter table public.users add column if not exists nickname text;

-- ให้ผู้จัด (organizer) อ่านชื่อเล่น/ชื่อ/เบอร์ ของ "ลูกค้าที่จองทริปของตัวเอง" ได้
-- เพื่อแสดงแผนผังที่นั่ง + รายชื่อผู้จอง (เห็นเฉพาะคนที่จองทริปของ organizer คนนั้น)
drop policy if exists "org_read_own_trip_customers" on public.users;
create policy "org_read_own_trip_customers"
  on public.users
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings b
      join public.trips t   on t.id = b.trip_id
      join public.organizers o on o.id = t.organizer_id
      where b.user_id = users.id
        and o.user_id = auth.uid()
    )
  );

-- ให้ผู้จัดอ่าน bookings ของทริปตัวเองได้
drop policy if exists "org_read_own_trip_bookings" on public.bookings;
create policy "org_read_own_trip_bookings"
  on public.bookings
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.trips t
      join public.organizers o on o.id = t.organizer_id
      where t.id = bookings.trip_id
        and o.user_id = auth.uid()
    )
  );
