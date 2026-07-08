-- SafeSummit — ให้หน้า Admin (anon key) มองเห็นทริปทุกสถานะ รวม "draft" ที่รออนุมัติ
--
-- ปัญหา: policy เดิมให้ public เห็นเฉพาะทริปที่เปิดขาย (open/full/ongoing/completed)
--        ทริป draft ที่ผู้จัดส่งขออนุมัติจึงถูกซ่อน หน้า Admin เลยไม่ขึ้นคำขออนุมัติ
--
-- ความปลอดภัย: หน้า Landing (js/db.js) กรองแสดงเฉพาะ open/full/ongoing/completed อยู่แล้ว
--             ต่อให้ policy นี้เปิดให้อ่าน draft ได้ ลูกค้าก็ยังไม่เห็น draft บนหน้าเว็บ
--             ข้อมูลทริปไม่ใช่ข้อมูลส่วนบุคคล (ชื่อทริป/ราคา/ผู้จัด) จึงเปิดอ่านได้
--
-- วิธีรัน: Supabase Dashboard → SQL Editor → วางโค้ดนี้ → Run

drop policy if exists "trips_public_select_all" on public.trips;

create policy "trips_public_select_all"
  on public.trips
  for select
  to anon, authenticated
  using (true);
