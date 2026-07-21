-- ============================================================
-- SafeSummit — Phase 19: LINE Booking Notification & Approval
--   คอลัมน์/ตารางสำหรับ flow แจ้งเตือน+อนุมัติผ่าน LINE
--   รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
--
-- หมายเหตุออกแบบ:
--   ใช้คอลัมน์ใหม่ `approval_status` แยกจาก `status`/`pay_status` เดิม
--   เพื่อไม่ให้กระทบ UI ที่พึ่ง status(confirmed/pending/cancelled) และ
--   pay_status(สลิป) อยู่แล้ว — การอนุมัติจาก LINE เป็นชั้น "อนุมัติการจอง"
--   ต่างหาก (ทีมงานยืนยันว่ารับจองจริง) เชื่อมกับ pay_status ทีหลังได้
-- ============================================================

-- 1) คอลัมน์บน bookings
alter table public.bookings add column if not exists approval_status  text default 'pending';  -- pending | approved | rejected
alter table public.bookings add column if not exists approved_by      text;                    -- ชื่อผู้กดใน LINE
alter table public.bookings add column if not exists approved_by_uid  text;                    -- LINE userId ผู้กด
alter table public.bookings add column if not exists approved_at       timestamptz;
alter table public.bookings add column if not exists customer_line_uid text;                    -- LINE uid ลูกค้า (ได้จาก LINE Login ตอนจอง)

create index if not exists bookings_approval_idx on public.bookings(approval_status);

-- 2) whitelist ผู้มีสิทธิ์กดอนุมัติในแชททีม (LINE userId)
create table if not exists public.authorized_approvers (
  line_uid   text primary key,          -- LINE userId (Uxxxxxxxx...)
  name       text not null,             -- ชื่อที่แสดงตอน reply เช่น "ปรัช"
  active     boolean default true,
  created_at timestamptz default now()
);
alter table public.authorized_approvers enable row level security;
-- ไม่สร้าง policy = client แตะไม่ได้ · service_role (Edge Function) ข้าม RLS อยู่แล้ว

-- 3) seed สมาชิกทีม 5 คน — **แก้ line_uid เป็นค่าจริงหลังได้ userId แต่ละคน**
--    วิธีหา userId: ให้แต่ละคนทักแชท OA ทีม แล้วดู source.userId ใน webhook log
insert into public.authorized_approvers (line_uid, name) values
  ('REPLACE_UID_PRUCH', 'ปรัช'),
  ('REPLACE_UID_JAY',   'เจ'),
  ('REPLACE_UID_JO',    'โจ้'),
  ('REPLACE_UID_CHOY',  'พี่ช้อย'),
  ('REPLACE_UID_FRANK', 'แฟรงค์')
on conflict (line_uid) do nothing;

-- 4) RPC atomic approve/reject (กัน race condition ถ้ากดซ้ำ/พร้อมกัน)
--    คืน true เฉพาะครั้งแรกที่เปลี่ยนจาก pending → decision อื่นจะได้ false
create or replace function public.line_decide_booking(
  p_booking_id uuid, p_decision text, p_by text, p_by_uid text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_row public.bookings;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'bad decision';
  end if;
  update public.bookings
     set approval_status = p_decision, approved_by = p_by, approved_by_uid = p_by_uid, approved_at = now()
   where id = p_booking_id and approval_status = 'pending'
   returning * into v_row;
  if not found then
    -- ถูกตัดสินไปแล้ว → คืนสถานะปัจจุบันให้ line-webhook แจ้ง "ดำเนินการไปแล้ว"
    select * into v_row from public.bookings where id = p_booking_id;
    return jsonb_build_object('changed', false,
      'status', coalesce(v_row.approval_status,'unknown'),
      'by', v_row.approved_by, 'customer_line_uid', v_row.customer_line_uid,
      'booking_ref', v_row.booking_ref);
  end if;
  return jsonb_build_object('changed', true,
    'status', v_row.approval_status, 'by', p_by,
    'customer_line_uid', v_row.customer_line_uid, 'booking_ref', v_row.booking_ref);
end $$;
revoke all on function public.line_decide_booking(uuid,text,text,text) from public, anon, authenticated;
-- เรียกผ่าน service_role (Edge Function) เท่านั้น
