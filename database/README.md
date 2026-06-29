# SafeSummit — Database

## Stack
- **Platform**: Supabase (PostgreSQL 15)
- **Auth**: Supabase Auth (built-in)
- **Storage**: Supabase Storage (สำหรับ slip_url, image_url)

## Files

| ไฟล์ | คำอธิบาย |
|------|---------|
| `schema_v1.sql` | Schema ล่าสุด — 7 ตาราง + triggers + RLS |

## Tables
```
users → organizers → trips → trip_itinerary
                         ↓
                      bookings → payments
                         ↓
                       reviews
```

## วิธี Deploy บน Supabase
1. สร้าง project ที่ https://supabase.com
2. ไปที่ **SQL Editor**
3. Paste ไฟล์ `schema_v1.sql` แล้วกด Run
4. อัปเดต `.env` ด้วย `SUPABASE_URL` และ `SUPABASE_ANON_KEY`

## Versioning
- Schema ใหม่ให้สร้างไฟล์ `schema_v2.sql` และลบ v1 ออก
