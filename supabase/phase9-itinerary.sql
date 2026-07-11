-- ============================================================
-- SafeSummit — Phase 9: กำหนดการทริป (itinerary) แก้ไขได้โดยผู้จัด
-- เก็บเป็น JSONB บน trips: [{"day":1,"time":"06:00","desc":"..."}, ...]
-- รันใน Supabase Dashboard → SQL Editor → Run
-- ============================================================

alter table public.trips add column if not exists itinerary jsonb;

-- ผู้จัดบันทึกกำหนดการได้เฉพาะ "ทริปของตัวเอง" (ผ่าน RPC security-definer)
create or replace function public.save_trip_itinerary(p_trip_id uuid, p_itinerary jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.trips t
     set itinerary = p_itinerary
    from public.organizers o
   where t.id = p_trip_id
     and o.id = t.organizer_id
     and o.user_id = auth.uid();
  if not found then
    raise exception 'ไม่มีสิทธิ์แก้ไขกำหนดการทริปนี้';
  end if;
end $$;
revoke all on function public.save_trip_itinerary(uuid, jsonb) from public, anon;
grant execute on function public.save_trip_itinerary(uuid, jsonb) to authenticated;
