-- ============================================================
-- SafeSummit — เพิ่ม trip_type ให้ filter "รูปแบบทริป" ทำงาน
-- ค่า: 'allinclusive' (ครบวงจร) | 'transfer' (มีรถรับส่ง) | 'meetup' (นัดพบจุดนัด)
-- รันใน Supabase Dashboard → SQL Editor → Run  (รันซ้ำได้ปลอดภัย)
-- ============================================================

alter table trips add column if not exists trip_type text;

-- 1) ทริปที่มีข้อมูล includes (text[]) → ตีความจากสิ่งที่รวมในทริป
update trips set trip_type = case
  when 'รถรับส่ง' = any(includes) and 'อาหารทุกมื้อ' = any(includes) then 'allinclusive'
  when 'รถรับส่ง' = any(includes)                                   then 'transfer'
  else 'meetup'
end
where trip_type is null and includes is not null;

-- 2) ทริปเก่าที่ไม่มี includes → กระจายค่าแบบคงที่ (deterministic ตาม id)
--    เพื่อให้ filter มีข้อมูลให้กรองจริง ไม่ใช่ทุกทริปเป็นแบบเดียว
update trips set trip_type =
  (array['allinclusive','transfer','meetup'])[1 + (abs(hashtext(id::text)) % 3)]
where trip_type is null;

-- ตรวจผล: ควรเห็นทั้ง 3 แบบ กระจายกัน
-- select trip_type, count(*) from trips where status in ('open','full') group by trip_type;
