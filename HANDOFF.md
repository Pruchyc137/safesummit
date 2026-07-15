# SafeSummit — สมุดส่งต่องาน (Team Handoff)

> **อ่านไฟล์นี้ก่อนเริ่มงานทุกครั้ง** และ **อัปเดต + commit** หลังทำเสร็จ
> ใช้ร่วมกัน 2 เครื่อง (PC หลัก + Surface Go) — Claude แต่ละเครื่องแยก session กัน ไฟล์นี้คือความจำกลางของทีม
>
> ธรรมเนียมการทำงาน: `git pull` ก่อนเริ่ม → ทำงาน → `git push` เมื่อเสร็จ · **ห้ามทำงาน 2 เครื่องพร้อมกันบนไฟล์เดียวกัน**

โฮสต์: GitHub Pages → https://pruchyc137.github.io/safesummit/ · push ขึ้น branch `main` = deploy อัตโนมัติ
Supabase: `wucrvtgpjqjxxqarzcpv` · Edge Function slug = `super-processor`

---

## ⏳ งานค้าง / ต้องทำโดยผู้ใช้ (สำคัญ)

- [ ] **Redeploy Edge Function `super-processor`** — โค้ดใน `supabase/functions/admin-customers/index.ts` มี action/field ใหม่ที่ยังไม่ deploy:
  - `name_en`, `images` ใน `update_trip` (Admin แก้ชื่ออังกฤษ + ผลตรวจรูปให้บันทึกถาวร)
  - `list_reviews`, `set_review_hidden`, `delete_review` (หน้า Admin → รีวิว)
  - วิธี: Supabase Dashboard → Edge Functions → super-processor → วางโค้ด → Deploy
- [ ] ตรวจว่ารัน SQL ครบ (ดูตารางด้านล่าง)

## 📦 SQL phases (รันใน Supabase SQL Editor)

| ไฟล์ | เรื่อง | สถานะ (ผู้ใช้ยืนยัน) |
|---|---|---|
| phase1–9 | schema/payment/RLS/seatlock/itinerary | ✅ รันแล้ว |
| phase10-trip-images.sql | bucket รูปทริป + policy | ✅ รันแล้ว |
| phase11-trip-image-gallery.sql | หลายรูป + เลือกปก | ✅ รันแล้ว |
| phase12-seat-status.sql | สถานะที่นั่ง "รอตรวจการชำระ" | ✅ รันแล้ว |
| phase13-public-reviews.sql | รีวิวจริงหน้าแรก | ✅ รันแล้ว |
| phase14-review-rules.sql | กติการีวิว (RPC + RLS) | ✅ รันแล้ว |
| phase15-review-moderation.sql | คอลัมน์ hidden + recent_reviews | ⚠️ ตรวจสอบ (คู่กับ redeploy Edge Function) |

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
