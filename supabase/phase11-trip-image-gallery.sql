-- ============================================================
-- SafeSummit — Phase 11: หลายรูปต่อทริป + เลือกปก + Admin ตรวจความเหมาะสม
-- images = [{ "url": "...", "ok": true|false|null }]
--   ok=true  อนุมัติ (โชว์ได้)   ok=false ไม่เหมาะสม (ซ่อน)   ok=null รอตรวจ
-- image_url = รูปปกที่เลือก (ต้องเป็นรูปที่ ok!=false) ถ้าว่าง/ถูกปฏิเสธ = ใช้รูป Default (ตามชื่อ/ภาค)
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

alter table public.trips add column if not exists images jsonb;

-- RPC: ผู้จัดตั้งรูป (ปก + คลังรูป) ของทริปตัวเอง — ใช้ตอนแก้ไขภายหลัง
create or replace function public.save_trip_images(p_trip_id uuid, p_cover text, p_images jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.trips t
     set image_url = p_cover,
         images    = p_images
    from public.organizers o
   where t.id = p_trip_id
     and o.id = t.organizer_id
     and o.user_id = auth.uid();
  if not found then
    raise exception 'ไม่มีสิทธิ์แก้ไขรูปทริปนี้';
  end if;
end $$;
revoke all on function public.save_trip_images(uuid, text, jsonb) from public, anon;
grant execute on function public.save_trip_images(uuid, text, jsonb) to authenticated;
