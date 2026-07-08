-- SafeSummit — เก็บ "เลขที่นั่งที่ลูกค้าเลือกจริง" ในการจอง
-- รูปแบบค่า: array ของสตริง เช่น {"v1-3","v1-4"}  (v{คัน}-{เลขที่นั่ง}, คันเริ่มที่ 1)
-- ใช้แสดงแผนผังรถตู้ฝั่งผู้จัดให้ตรงกับที่นั่งที่ลูกค้าเลือก
--
-- วิธีรัน: Supabase Dashboard → SQL Editor → วาง → Run

alter table public.bookings add column if not exists seat_numbers text[];
