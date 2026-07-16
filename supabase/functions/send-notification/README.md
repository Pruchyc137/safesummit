# SafeSummit — Email Notifications (Edge Function)

`send-notification` ส่งอีเมลแจ้งลูกค้าอัตโนมัติเมื่อ:
- จองทริปสำเร็จ (booking ใหม่)
- ชำระเงินได้รับการยืนยัน (ครบ/มัดจำ)
- การชำระเงินถูกปฏิเสธ
- คืนเงินเสร็จแล้ว (Admin กด "โอนคืนแล้ว")

ทำงานผ่าน **Supabase Database Webhook** — ไม่ต้องแก้โค้ดหน้าเว็บใดๆ เลย เพราะ Webhook
จะยิงมาหาฟังก์ชันนี้เองทุกครั้งที่ตาราง `bookings` มีการ insert/update (ไม่ว่าจะแก้จากที่ไหน)

## ขั้นตอนที่ 1 — สมัคร Resend (ผู้ส่งอีเมล)

1. ไปที่ https://resend.com → สมัครบัญชีฟรี (3,000 อีเมล/เดือนฟรี)
2. ไปที่ **API Keys** → สร้าง key ใหม่ → คัดลอกเก็บไว้
3. **สำคัญ**: ถ้ายังไม่ verify โดเมนของตัวเอง Resend จะให้ส่งได้จริงแค่หาอีเมลที่สมัคร
   Resend ไว้เท่านั้น (โหมดทดสอบ) — ถ้าจะส่งหาลูกค้าจริงทุกคน ต้องไปที่ **Domains** →
   เพิ่มโดเมนของ SafeSummit แล้วตั้งค่า DNS record ตามที่ Resend บอก (ใช้เวลาไม่กี่นาที
   ถ้าโดเมนอยู่กับผู้ให้บริการที่ตั้งค่า DNS เองได้)

## ขั้นตอนที่ 2 — Deploy function + ตั้งค่า secrets

```bash
supabase functions deploy send-notification --no-verify-jwt

supabase secrets set RESEND_API_KEY=<API key จาก Resend>
supabase secrets set RESEND_FROM="SafeSummit <onboarding@resend.dev>"   # หรือใช้โดเมนที่ verify แล้ว เช่น booking@safesummit.co.th
supabase secrets set WEBHOOK_SECRET=<ตั้งรหัสลับยาวๆ ของคุณเอง ไม่ต้องเหมือน ADMIN_API_KEY>
```

## ขั้นตอนที่ 3 — ตั้งค่า Database Webhook

1. Supabase Dashboard → **Database → Webhooks** → **Create a new hook**
2. Name: `booking-notifications`
3. Table: `bookings`
4. Events: ✅ Insert ✅ Update (ไม่ต้องติ๊ก Delete)
5. Type: **HTTP Request**
6. Method: `POST`
7. URL: `https://wucrvtgpjqjxxqarzcpv.supabase.co/functions/v1/send-notification`
8. HTTP Headers → Add header:
   - Name: `x-webhook-secret`
   - Value: ค่า `WEBHOOK_SECRET` ที่ตั้งไว้ในขั้นตอนที่ 2 (ต้องตรงกันเป๊ะ)
9. กด **Create webhook**

## ทดสอบ

ลองจองทริปใหม่ 1 รายการ (หรือให้ Admin กดอนุมัติ/ปฏิเสธการชำระเงินของ booking ที่มีอยู่)
แล้วเช็คว่าอีเมลเข้า inbox ของลูกค้าคนนั้นไหม ถ้าไม่เข้า เช็ค:
- Supabase Dashboard → Edge Functions → send-notification → **Logs** (ดู error)
- Resend Dashboard → **Logs** (ดูว่าส่งสำเร็จ/ถูกบล็อกเพราะโดเมนยังไม่ verify)
