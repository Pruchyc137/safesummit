-- ============================================================
-- SafeSummit — Phase 15: Admin ดูแลรีวิว (ซ่อน/ลบรีวิวไม่เหมาะสม)
--   • เพิ่มคอลัมน์ hidden — รีวิวที่ถูกซ่อนจะไม่ขึ้นหน้าแรก
--   • อัปเดต recent_reviews ให้ข้ามรีวิวที่ถูกซ่อน
--   • การซ่อน/ลบจริงทำผ่าน Edge Function (service_role) — ดู super-processor
-- รันใน Supabase Dashboard → SQL Editor → Run  (ครั้งเดียว)
-- ============================================================

alter table public.reviews add column if not exists hidden boolean default false;

-- โชว์หน้าแรกเฉพาะรีวิวที่ไม่ถูกซ่อน
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
  where coalesce(btrim(r.comment), '') <> ''
    and coalesce(r.hidden, false) = false          -- ข้ามรีวิวที่ถูกซ่อน
  order by r.created_at desc nulls last
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;
revoke all on function public.recent_reviews(int) from public;
grant execute on function public.recent_reviews(int) to anon, authenticated;
