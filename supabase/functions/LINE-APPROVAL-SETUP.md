# LINE Booking Notification & Approval — คู่มือติดตั้ง

ระบบ: ลูกค้าจอง → แจ้งกลุ่มไลน์ทีม (OA ทีม) → ทีมกดอนุมัติ/ปฏิเสธในแชท → อัปเดต DB → แจ้งลูกค้า (OA ลูกค้า)

ไฟล์ที่เกี่ยวข้อง:
- `supabase/phase19-line-approval.sql` — คอลัมน์ + ตาราง + RPC
- `supabase/functions/notify-team/index.ts` — DB webhook → push กลุ่มทีม
- `supabase/functions/line-webhook/index.ts` — รับปุ่ม → verify → อนุมัติ → แจ้งลูกค้า

> **ออกแบบ:** ใช้คอลัมน์ใหม่ `approval_status` (pending/approved/rejected) แยกจาก `status` และ `pay_status` เดิม ไม่กระทบ UI ที่มีอยู่ · ถ้าต้องการให้ LINE-approve ไปเปลี่ยน pay_status ด้วย ค่อยเชื่อมทีหลัง

---

## ขั้นตอนติดตั้ง (ทำครั้งเดียว)

### 1. รัน SQL
Supabase Dashboard → SQL Editor → วาง `phase19-line-approval.sql` → Run

### 2. เตรียม LINE Official Account 2 ตัว
| | ใช้ทำอะไร | เอาอะไรมา |
|---|---|---|
| **OA ทีม** (สร้างใหม่) | แจ้ง+อนุมัติในกลุ่มทีม | Channel access token, Channel secret |
| **OA ลูกค้า** (มีแล้ว) | แจ้งลูกค้า | Channel access token |
ทั้งคู่เปิด **Messaging API** (LINE Developers Console → ช่อง Messaging API)

### 3. เอา OA ทีมเข้ากลุ่มไลน์ทีม + หา groupId
- เชิญ OA ทีมเข้ากลุ่มไลน์ของทีม 5 คน
- ตั้ง webhook (ขั้นตอน 5) ก่อน แล้วพิมพ์อะไรก็ได้ในกลุ่ม → ดู log ของ `line-webhook` จะเห็น `source.groupId` (ขึ้นต้น `C...`) → เอาไปตั้ง `TEAM_LINE_GROUP_ID`

### 4. หา LINE userId ของทีม 5 คน (สำหรับ whitelist)
- ให้แต่ละคนทักแชท OA ทีม (หรือพิมพ์ในกลุ่ม) → ดู log เห็น `source.userId` (ขึ้นต้น `U...`)
- อัปเดตตาราง: `update authorized_approvers set line_uid='Uxxxx' where name='ปรัช';` (ทำครบ 5 คน)

### 5. Deploy Edge Functions + ตั้ง ENV
```bash
supabase functions deploy notify-team  --no-verify-jwt
supabase functions deploy line-webhook --no-verify-jwt

# ENV (Dashboard → Edge Functions → Secrets หรือ supabase secrets set)
supabase secrets set TEAM_LINE_CHANNEL_TOKEN=xxx
supabase secrets set TEAM_LINE_CHANNEL_SECRET=xxx
supabase secrets set TEAM_LINE_GROUP_ID=Cxxxx
supabase secrets set CUSTOMER_LINE_CHANNEL_TOKEN=xxx
supabase secrets set NOTIFY_WEBHOOK_SECRET=<สุ่มยาวๆ>
```
(`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` Supabase ใส่ให้อัตโนมัติ)

### 6. ตั้ง Webhook ของ OA ทีม
LINE Developers → OA ทีม → Messaging API → **Webhook URL** =
`https://wucrvtgpjqjxxqarzcpv.functions.supabase.co/line-webhook`
เปิด **Use webhook** = ON · ปิด auto-reply/greeting

### 7. ตั้ง Database Webhook (ยิงตอนมีจองใหม่)
Supabase Dashboard → Database → Webhooks → Create
- Table: `public.bookings` · Event: **INSERT**
- Type: HTTP Request · URL: `https://wucrvtgpjqjxxqarzcpv.functions.supabase.co/notify-team`
- HTTP Header เพิ่ม: `x-webhook-secret: <ค่าเดียวกับ NOTIFY_WEBHOOK_SECRET>`

---

## ทดสอบ
1. จองทริปบนเว็บ 1 รายการ → กลุ่มไลน์ทีมควรได้การ์ด + ปุ่มอนุมัติ/ปฏิเสธ
2. คนใน whitelist กด ✅ → กลุ่มขึ้น "อนุมัติแล้วโดย [ชื่อ]" + `bookings.approval_status='approved'`
3. กดซ้ำ / คนอื่นกด → ขึ้น "ถูกอนุมัติไปแล้วโดย [ชื่อ]" (ไม่เปลี่ยนซ้ำ = กัน race แล้ว)
4. คนนอก whitelist กด → "คุณไม่มีสิทธิ์อนุมัติ"

## ความปลอดภัยที่ทำไว้
- ✅ verify `x-line-signature` (HMAC-SHA256) ทุก request ก่อนประมวลผล
- ✅ whitelist `authorized_approvers` ทุกครั้งก่อนอนุมัติ
- ✅ อัปเดต atomic ผ่าน RPC `line_decide_booking` (เปลี่ยน pending → decision ได้ครั้งเดียว)
- ✅ DB webhook ป้องกันด้วย `x-webhook-secret`

---

## ⏳ ยังขาด: LINE Login เก็บ `customer_line_uid` (จำเป็นสำหรับ "แจ้งลูกค้า" ขั้นที่ 6)

ตอนนี้ระบบ **แจ้งทีม + อนุมัติ ครบแล้ว** แต่ "แจ้งลูกค้ากลับ" จะทำงานเฉพาะเมื่อ booking มี `customer_line_uid` ซึ่งต้องเก็บตอนจองผ่าน **LINE Login** บนเว็บ

สิ่งที่ต้องทำเพิ่ม (แยกเป็น phase ถัดไป):
1. สร้าง **LINE Login channel** อยู่ใน **Provider เดียวกับ OA ลูกค้า** (สำคัญ — userId ถึงจะตรงกัน push หาลูกค้าได้)
2. หน้า `booking.html` เพิ่มปุ่ม "เชื่อม LINE" → OAuth → ได้ `userId` → เก็บลง `bookings.customer_line_uid` ตอน insert
3. ลูกค้าต้อง **เป็นเพื่อนกับ OA ลูกค้า** ด้วย ไม่งั้น push ไม่ถึง

> บอกทีมได้ถ้าจะให้ทำ LINE Login ต่อ — ต้องมี LINE Login channel id ก่อน
