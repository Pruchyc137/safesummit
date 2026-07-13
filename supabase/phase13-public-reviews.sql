-- ============================================================
-- SafeSummit — Phase 13: รีวิวจริงจากลูกค้าขึ้นหน้าแรก
-- ลูกค้าเขียนรีวิวได้จากหน้า "ทริปของฉัน" (my-trips.html) อยู่แล้ว →
-- ฟังก์ชันนี้ดึงรีวิว "ล่าสุดที่มีข้อความ" มาโชว์หน้าแรกแบบปลอดภัย
-- คืนแค่ ชื่อที่แสดง (ชื่อเล่น/ชื่อต้น) — ไม่เผยอีเมล/ชื่อเต็ม/ข้อมูลส่วนตัว
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

-- กันกรณีตาราง reviews ยังไม่มีคอลัมน์ created_at
alter table public.reviews add column if not exists created_at timestamptz default now();

create or replace function public.recent_reviews(p_limit int default 12)
returns table(rating int, comment text, reviewer text, trip_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select r.rating,
         r.comment,
         coalesce(
           nullif(btrim(u.nickname), ''),
           nullif(split_part(btrim(coalesce(u.full_name, '')), ' ', 1), ''),
           'นักเดินป่า'
         ) as reviewer,
         coalesce(t.name_th, '') as trip_name,
         r.created_at
  from public.reviews r
  left join public.users u on u.id = r.user_id
  left join public.trips  t on t.id = r.trip_id
  where coalesce(btrim(r.comment), '') <> ''      -- เฉพาะรีวิวที่มีข้อความ
  order by r.created_at desc nulls last
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;
revoke all on function public.recent_reviews(int) from public;
grant execute on function public.recent_reviews(int) to anon, authenticated;
