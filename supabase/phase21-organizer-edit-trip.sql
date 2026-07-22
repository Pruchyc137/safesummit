-- ============================================================
-- SafeSummit — Phase 21: ผู้จัดขอแก้ไขทริปของตัวเอง
--   แก้บั๊ก: organizer.html อัปเดตตาราง trips ตรงๆ → RLS บล็อก → "บันทึกไม่สำเร็จ"
--   (แบบเดียวกับ save_trip_itinerary / save_trip_image ที่ต้องผ่าน RPC)
--
-- นโยบายการอนุมัติ:
--   • "ลดราคา" (และแก้คำอธิบาย) = มีผลทันที ทริปยังเปิดขายอยู่
--     → รองรับเคส "ทัวร์ไฟไหม้" ใกล้วันเดินทางแต่คนไม่เต็ม ต้องลดราคาเร่งด่วน
--       ถ้าบังคับ draft ทริปจะหายจากเว็บระหว่างรออนุมัติ = ขายไม่ได้เลย
--   • แก้อย่างอื่น (ขึ้นราคา / เปลี่ยนวัน / เปลี่ยนชื่อ / ลดที่นั่ง) = ส่งให้ Admin อนุมัติ
--     (ตั้ง status='draft' เหมือนเดิม) เพราะกระทบคนที่จองไปแล้ว
--
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

-- 0) คอลัมน์ note ไม่เคยมีในตาราง trips (ตรวจพบจาก error จริง:
--    'column "note" of relation "trips" does not exist')
--    ทั้งที่โค้ดหลายที่พึ่งมันอยู่ → ระบบ "ขอแก้ไข/ขอยกเลิกทริป" จึงไม่เคยทำงานเลย
--    • organizer.html: ขอยกเลิกทริป เขียน note '[ขอยกเลิก] ...'
--    • admin.html: แท็บ "คำขอแก้ไข/ยกเลิก" ตรวจจาก note ที่ขึ้นต้นด้วย '[ขอ'
--    • Edge Function update_trip: อนุญาตเขียน note
alter table public.trips add column if not exists note text;

create or replace function public.organizer_request_trip_edit(
  p_trip_id     uuid,
  p_name        text,
  p_start       date,
  p_price       numeric,
  p_capacity    int,
  p_trip_type   text,
  p_description text,
  p_reason      text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t         public.trips;
  v_safe    boolean;
  v_mode    text;
begin
  -- ต้องเป็นทริปของผู้จัดที่ล็อกอินอยู่เท่านั้น
  select tr.* into t
    from public.trips tr
    join public.organizers o on o.id = tr.organizer_id
   where tr.id = p_trip_id and o.user_id = auth.uid();
  if not found then
    raise exception 'ไม่มีสิทธิ์แก้ไขทริปนี้ (ไม่ใช่ทริปของคุณ หรือไม่พบทริป)';
  end if;

  if coalesce(btrim(p_reason),'') = '' then
    raise exception 'กรุณาระบุเหตุผลในการแก้ไข';
  end if;

  -- เป็น "การแก้ที่ไม่กระทบลูกค้า" ไหม → ลดราคา/เท่าเดิม + ไม่แก้ชื่อ/วัน/ที่นั่ง
  v_safe := (coalesce(p_price, t.price_per_person) <= t.price_per_person)
        and (coalesce(nullif(btrim(p_name),''), t.name_th) = t.name_th)
        and (coalesce(p_start, t.start_date) = t.start_date)
        and (coalesce(p_capacity, t.capacity) >= t.capacity);

  if v_safe then
    v_mode := 'live';           -- มีผลทันที ทริปยังเปิดขาย
    update public.trips
       set price_per_person = coalesce(p_price, price_per_person),
           description      = coalesce(p_description, description),
           trip_type        = coalesce(nullif(btrim(p_trip_type),''), trip_type),
           note             = '[ลดราคา] ' || p_reason
     where id = p_trip_id;
  else
    v_mode := 'pending';        -- ต้องให้ Admin อนุมัติก่อน
    update public.trips
       set name_th          = coalesce(nullif(btrim(p_name),''), name_th),
           start_date       = coalesce(p_start, start_date),
           price_per_person = coalesce(p_price, price_per_person),
           capacity         = coalesce(p_capacity, capacity),
           trip_type        = coalesce(nullif(btrim(p_trip_type),''), trip_type),
           description      = coalesce(p_description, description),
           status           = 'draft',
           note             = '[ขอแก้ไข] ' || p_reason
     where id = p_trip_id;
  end if;

  return jsonb_build_object('mode', v_mode);
end $$;

revoke all on function public.organizer_request_trip_edit(uuid,text,date,numeric,int,text,text,text) from public, anon;
grant execute on function public.organizer_request_trip_edit(uuid,text,date,numeric,int,text,text,text) to authenticated;
