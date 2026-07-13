-- ============================================================
-- SafeSummit — Phase 14: กติกาการรีวิว (บังคับที่ระดับฐานข้อมูล)
--   • รีวิวได้เฉพาะ "ทริปที่ไปมาแล้ว" (trip.status = completed) + จ่ายเงินแล้ว
--   • ต้องเป็นการจองของตัวเองเท่านั้น
--   • 1 การจอง = รีวิวได้ 1 ครั้ง (แก้ไขรีวิวเดิมได้ แต่ไม่เพิ่มซ้ำ)
--   • คนที่ยังไม่เคยไป / ไม่ได้จ่าย → รีวิวไม่ได้
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

-- 1 รีวิว ต่อ 1 การจอง
create unique index if not exists reviews_booking_unique on public.reviews(booking_id);

-- ปิดการเขียนตรงจาก client — ต้องเขียนผ่าน submit_review() เท่านั้น (อ่านได้สาธารณะ)
alter table public.reviews enable row level security;
do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname='public' and tablename='reviews' loop
    execute format('drop policy %I on public.reviews', p.policyname);
  end loop;
end $$;
create policy "reviews public read" on public.reviews for select using (true);

-- ลูกค้าส่งรีวิว (ตรวจสิทธิ์ครบก่อนบันทึก)
create or replace function public.submit_review(p_booking_id uuid, p_rating int, p_comment text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_trip uuid;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'กรุณาให้คะแนน 1–5 ดาว';
  end if;

  -- ต้องเป็นการจองของตัวเอง + ทริปจบแล้ว (ได้ไปมาจริง) + ชำระเงินแล้ว
  select b.trip_id into v_trip
  from public.bookings b
  join public.trips t on t.id = b.trip_id
  where b.id = p_booking_id
    and b.user_id = auth.uid()
    and b.pay_status in ('verified','partial')
    and t.status = 'completed';

  if v_trip is null then
    raise exception 'รีวิวได้เฉพาะทริปที่คุณเดินทางไปมาแล้วและชำระเงินแล้วเท่านั้น';
  end if;

  insert into public.reviews (booking_id, trip_id, user_id, rating, comment, created_at)
  values (p_booking_id, v_trip, auth.uid(), p_rating, nullif(btrim(p_comment), ''), now())
  on conflict (booking_id) do update
    set rating = excluded.rating, comment = excluded.comment;
end $$;
revoke all on function public.submit_review(uuid, int, text) from public, anon;
grant execute on function public.submit_review(uuid, int, text) to authenticated;
