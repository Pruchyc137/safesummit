# SafeSummit — สมุดส่งต่องาน (Team Handoff)

> **อ่านไฟล์นี้ก่อนเริ่มงานทุกครั้ง** และ **อัปเดต + commit** หลังทำเสร็จ
> ใช้ร่วมกัน 2 เครื่อง (PC หลัก + Surface Go) — Claude แต่ละเครื่องแยก session กัน ไฟล์นี้คือความจำกลางของทีม
>
> ธรรมเนียมการทำงาน: `git pull` ก่อนเริ่ม → ทำงาน → `git push` เมื่อเสร็จ · **ห้ามทำงาน 2 เครื่องพร้อมกันบนไฟล์เดียวกัน**

โฮสต์: GitHub Pages → https://pruchyc137.github.io/safesummit/ · push ขึ้น branch `main` = deploy อัตโนมัติ
Supabase: `wucrvtgpjqjxxqarzcpv` · Edge Function slug = `super-processor`

---

## ⏳ งานค้าง / ต้องทำโดยผู้ใช้ (สำคัญ)

- [x] **Redeploy Edge Function `super-processor`** — ผู้ใช้ยืนยันแล้วว่า deploy โค้ดล่าสุดจาก `supabase/functions/admin-customers/index.ts` เรียบร้อย (`name_en`, `images` ใน `update_trip`; `list_reviews`, `set_review_hidden`, `delete_review`)
- [x] ตรวจว่ารัน SQL ครบ — ผู้ใช้ยืนยันแล้ว (ดูตารางด้านล่าง)
- [x] **รัน `phase16-cancellation-refunds.sql`** — ผู้ใช้ยืนยันแล้ว
- [x] **Redeploy Edge Function `super-processor` อีกรอบ** — ผู้ใช้ยืนยันแล้ว (เพิ่ม action `list_pending_refunds` / `mark_refund_paid`) — ฟีเจอร์ "รอคืนเงินลูกค้า" ใช้งานได้จริงแล้ว
- [ ] **ระบบแจ้งเตือนอีเมล (ใหม่ — พักไว้ก่อนตามที่ผู้ใช้ขอ)** — ดู `supabase/functions/send-notification/README.md` ต้องทำ 3 ขั้นตอน: (1) สมัคร Resend + เอา API key, (2) deploy function `send-notification` + ตั้ง secrets 3 ตัว (`RESEND_API_KEY`, `RESEND_FROM`, `WEBHOOK_SECRET`), (3) ตั้งค่า Database Webhook บนตาราง `bookings` ใน Supabase Dashboard ให้ยิงมาที่ function นี้ — ยังไม่มีอีเมลส่งออกจนกว่าจะทำครบ 3 ขั้นตอน

## 📦 SQL phases (รันใน Supabase SQL Editor)

| ไฟล์ | เรื่อง | สถานะ (ผู้ใช้ยืนยัน) |
|---|---|---|
| phase1–9 | schema/payment/RLS/seatlock/itinerary | ✅ รันแล้ว |
| phase10-trip-images.sql | bucket รูปทริป + policy | ✅ รันแล้ว |
| phase11-trip-image-gallery.sql | หลายรูป + เลือกปก | ✅ รันแล้ว |
| phase12-seat-status.sql | สถานะที่นั่ง "รอตรวจการชำระ" | ✅ รันแล้ว |
| phase13-public-reviews.sql | รีวิวจริงหน้าแรก | ✅ รันแล้ว |
| phase14-review-rules.sql | กติการีวิว (RPC + RLS) | ✅ รันแล้ว |
| phase15-review-moderation.sql | คอลัมน์ hidden + recent_reviews | ✅ รันแล้ว |
| phase16-cancellation-refunds.sql | refund tracking (bookings) + ตาราง refund_reviews | ✅ รันแล้ว |

---

## ✅ ฟีเจอร์ที่ทำเสร็จแล้ว (deploy บน main แล้ว)

- Admin Dashboard drill-down + หน้า "สรุปผู้จัด" (filter รายผู้จัด)
- หน้า "การจองลูกค้า" ดึงผ่าน Edge Function (แก้ enum pay_status)
- หน้าแรกโชว์ทริปที่ยังไม่ใส่รูป (fallback scene) + รูป `images/lelosu.jpg`
- รูปทริป: อัปหลายรูป + ผู้จัดเลือกปก + Admin ตรวจเหมาะสม/ใช้ default + ปุ่มแปลงชื่อไทย→อังกฤษ
- กำหนดการขึ้นตอนสร้างทริป (มี default + วันเดินทางไป = ก่อนวันเริ่ม 1 วัน)
- "สิ่งที่รวมในราคา" พิมพ์เพิ่มเองได้
- Badge เป็น read-only (Admin กำหนด)
- ที่นั่งแยกสถานะ "รอตรวจการชำระ" (ผู้จัด/Admin/ลูกค้า)
- แยกบทบาท: บัญชีผู้จัดจองทริปไม่ได้ · หน้า login แยกลูกค้า/ผู้จัด · ปุ่มหน้าแรกเป็น dropdown · เอา Google/FB ออก
- รีวิว: โชว์จริงหน้าแรก + กติกา (ไปทริปมาแล้ว+จ่ายแล้ว+ครั้งเดียว) + Admin ซ่อน/ลบ
- ลงทะเบียนทริป: จังหวัดเป็น dropdown ตามภาค · ปฏิทิน range เลือกวันไป-กลับ (Agoda-style) → จำนวนวันคำนวณเอง ผูกกับกำหนดการ

## 🗺️ ไฟล์หลัก
- `index.html` landing · `trip.html` รายละเอียด · `booking.html` จอง · `my-trips.html` ทริปลูกค้า
- `organizer.html` แดชบอร์ดผู้จัด · `admin.html` แดชบอร์ด Admin · `login.html` เข้าสู่ระบบ
- `js/db.js` Supabase helpers · `supabase/` SQL + Edge Function

---

## 📝 บันทึกล่าสุด
- (อัปเดตบรรทัดนี้ทุกครั้งที่ทำงานเสร็จ — ใคร/เครื่องไหน/ทำอะไร/commit)
- PC หลัก: ตั้งค่าระบบส่งต่องานทีม 2 เครื่อง + สร้างไฟล์นี้
- Surface Go: ยืนยัน redeploy Edge Function `super-processor` และรัน `phase15-review-moderation.sql` เรียบร้อยแล้ว (ผู้ใช้ทำผ่าน Supabase Dashboard เอง) — ไม่มีการแก้โค้ดเพิ่มในรอบนี้
- Surface Go: **🔴 พบว่า `admin-accounts.js` และ `SafeSummit_Admin_Credentials.xlsx` (มี `ADMIN_API_KEY` จริงอยู่ข้างใน) ถูก commit ขึ้น public GitHub repo มาตลอด** — แก้แล้ว: (1) rotate password 3 บัญชี admin ใน `admin-accounts.js`, (2) ผู้ใช้ตั้งค่า `ADMIN_API_KEY` ใหม่บน Supabase Secrets เอง, (3) เพิ่ม `.gitignore` + เอา `SafeSummit_Admin_Credentials.xlsx` ออกจาก git tracking (ไฟล์ยังอยู่ในเครื่องแต่ละคน ไม่ push ขึ้น GitHub อีกต่อไป) — **⚠️ ค่าเก่ายังอยู่ใน git history เก่า (ไม่ได้ purge) แต่ใช้งานไม่ได้แล้วเพราะ rotate ไปแล้ว** · **ใครก็ตามที่ยังใช้ `SafeSummit_Admin_Credentials.xlsx` เวอร์ชันเก่าในเครื่องตัวเอง ให้โหลดค่าล่าสุดจากเครื่อง Surface Go หรือถามทีมสำหรับรหัสผ่าน/key ใหม่** — commit: `078c5bb`
- Surface Go: **แก้ปัญหา "คืนเงินแล้ว" ปลอม** — ก่อนหน้านี้ตอนลูกค้ายกเลิกทริป หน้า `my-trips.html` โชว์ว่า "คืนเงินแล้ว" ทันทีทั้งที่ไม่มีการโอนเงินจริงและไม่มีที่ไหนบันทึกให้ Admin เห็นเลย (เขียนแค่ `status:'cancelled'` ลง DB) ตอนนี้: (1) ลูกค้ายกเลิก → บันทึก `cancelled_at/cancel_reason/refund_pct/refund_amount/refund_status='pending'` ลง `bookings` จริง + ข้อความเปลี่ยนเป็น "ส่งคำขอยกเลิกแล้ว รอ Admin ดำเนินการ" ไม่ใช่ "คืนเงินแล้ว", (2) เพิ่มแผงใหม่ในหน้า Admin → การเงิน → "รอคืนเงินลูกค้า" ให้เห็นคิว + เบอร์โทร/LINE ลูกค้า + กดยืนยัน "โอนคืนแล้ว" ได้จริงหลังโอนเงินเสร็จ (action ใหม่ `list_pending_refunds`/`mark_refund_paid` ใน Edge Function) — deploy ครบแล้ว (phase16 SQL + redeploy Edge Function ผู้ใช้ยืนยัน) ใช้งานได้จริง — commit: `8dee5e2`
- Surface Go: **เพิ่ม Edge Function `send-notification`** — ส่งอีเมลแจ้งลูกค้าอัตโนมัติผ่าน Database Webhook (จอง/ชำระเงินยืนยัน-มัดจำ-ปฏิเสธ/คืนเงินสำเร็จ) ใช้ Resend — **ยังไม่ deploy** ผู้ใช้ขอพักไว้ก่อน ดูขั้นตอนเต็มใน `supabase/functions/send-notification/README.md` — commit: `be8a617`
- Surface Go: **เพิ่มหน้ากฎหมาย** — `terms.html` (ข้อกำหนดการใช้งาน), `privacy.html` (นโยบายความเป็นส่วนตัว/PDPA), `refund-policy.html` (นโยบายคืนเงิน ตรงกับอัตราจริงใน `my-trips.html`) แก้ลิงก์ dead link ใน footer + checkbox สมัครสมาชิกให้ชี้มาที่หน้าจริงแล้ว — **เอกสารทั้ง 3 หน้าเป็นฉบับร่างเริ่มต้น ยังไม่ผ่านนักกฎหมายตรวจ ควรให้ผู้เชี่ยวชาญตรวจสอบก่อนเปิดใช้งานจริง** — commit: `6cae9ed`
- Surface Go: **แก้ปุ่ม "ถัดไป" ในหน้าจอง step 1 ไม่เตือนเมื่อข้อมูลไม่ครบ** — เดิมมีแค่ toast (popup ชั่วคราว หายไว พลาดง่าย) ตอนนี้เพิ่มข้อความแดงถาวรใต้ปุ่ม + กรอบแดงไฮไลต์จุดที่ขาด (ที่นั่ง/ติ๊กยอมรับเงื่อนไข) หายเองอัตโนมัติเมื่อผู้ใช้แก้ไข — commit: `a487b34`
- Surface Go: **ลบ seed trips/organizers ปลอมออกจาก production DB สำเร็จ** — 30 ทริป + 7 ผู้จัด seed (จาก `010_seed_trips_only.sql`, ไม่เคยสมัครผ่าน organizer.html จริง) รวมถึง booking ทดสอบของเจ้าของระบบเองที่ติดอยู่ — ผู้ใช้ยืนยันแล้วว่าไม่มีลูกค้าจริงปนอยู่ก่อนลบ, รันผ่าน SQL Editor เรียบร้อย ตรวจสอบแล้วเหลือ 0 ทริป seed — ใช้ `supabase/phase17-remove-seed-trips.sql` เป็นอ้างอิง (ไฟล์นี้มี delete section ครอบด้วย `/* */` comment ต้องเลือกเฉพาะโค้ดข้างในรัน ไม่ใช่รันทั้งไฟล์)
