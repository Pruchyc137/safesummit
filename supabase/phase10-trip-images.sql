-- ============================================================
-- SafeSummit — Phase 10: รูปทริป (trip-images) อัปโหลดขึ้น Supabase Storage
-- ทำให้ "ใส่รูปแล้วขึ้นเลย" ไม่ต้อง push โค้ด/รูปใหม่ทุกครั้ง
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

-- 1) bucket public-read (ถ้ามีอยู่แล้วก็แค่ set ให้ public)
insert into storage.buckets (id, name, public)
values ('trip-images', 'trip-images', true)
on conflict (id) do update set public = true;

-- 2) นโยบายไฟล์ใน bucket นี้
--    - ใครก็อ่าน/ดูรูปได้ (public read)
--    - เฉพาะผู้ใช้ที่ล็อกอิน (ผู้จัด) อัป/แก้รูปได้
drop policy if exists "trip-images public read"  on storage.objects;
create policy "trip-images public read" on storage.objects
  for select to public using (bucket_id = 'trip-images');

drop policy if exists "trip-images auth insert" on storage.objects;
create policy "trip-images auth insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'trip-images');

drop policy if exists "trip-images auth update" on storage.objects;
create policy "trip-images auth update" on storage.objects
  for update to authenticated
  using (bucket_id = 'trip-images') with check (bucket_id = 'trip-images');

drop policy if exists "trip-images auth delete" on storage.objects;
create policy "trip-images auth delete" on storage.objects
  for delete to authenticated using (bucket_id = 'trip-images');

-- 3) RPC: ผู้จัดตั้ง/เปลี่ยน "รูป" ของทริปตัวเอง (แก้ image_url ของทริปที่มีอยู่)
--    การสร้างทริปใหม่ตั้ง image_url ตอน insert ได้อยู่แล้ว — อันนี้ไว้ตอน "แก้ไขทริป"
create or replace function public.save_trip_image(p_trip_id uuid, p_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.trips t
     set image_url = p_url
    from public.organizers o
   where t.id = p_trip_id
     and o.id = t.organizer_id
     and o.user_id = auth.uid();
  if not found then
    raise exception 'ไม่มีสิทธิ์แก้ไขรูปทริปนี้';
  end if;
end $$;
revoke all on function public.save_trip_image(uuid, text) from public, anon;
grant execute on function public.save_trip_image(uuid, text) to authenticated;
