# SafeSummit — ความปลอดภัยลูกค้า & ผู้จัด (PDCA)

> เอกสารนี้ใช้เป็นรอบทำงานต่อเนื่อง ไม่ใช่เช็คลิสต์ครั้งเดียวจบ
> อัปเดตล่าสุด: 10 ก.ค. 2569

---

## หลักการตั้งต้น
ระบบนี้ **จ่ายเงินจริง** และเก็บ **ข้อมูลส่วนบุคคล** (เลขบัตรประชาชน, บัญชีธนาคาร, สลิป)
`anon key` ฝังอยู่ใน source ของเว็บ → **ถือว่าเป็นข้อมูลสาธารณะ ใครก็ยิง API ได้**
ดังนั้นความปลอดภัยต้องอยู่ที่ **ฐานข้อมูล (RLS + GRANT)** ไม่ใช่ที่หน้าเว็บ

---

## P — PLAN (สิ่งที่ต้องปกป้อง)

| ทรัพย์สิน | ความเสี่ยงถ้าหลุด | ระดับ |
|---|---|---|
| `payment_qr_url` ของผู้จัด | ถูกสลับ → เงินลูกค้าเข้าคนร้าย | 🔴 วิกฤต |
| `organizers.bank_account`, `id_card` | ขโมยตัวตน / ฉ้อโกง | 🔴 สูง |
| `users.id_card`, `phone`, `line_id` | ข้อมูลส่วนบุคคลลูกค้ารั่ว | 🔴 สูง |
| สลิปโอนเงิน (`slips`) | มีเลขบัญชี/ชื่อจริง | 🟠 กลาง |
| `bookings.pay_status`, `paid_amount` | ปลอมสถานะจ่ายเงิน | 🔴 สูง |
| `trips.status` | ปล่อยทริปปลอมขึ้นหน้าเว็บ | 🟠 กลาง |

**กฎ 3 ข้อ**
1. **อ่าน**: anon เห็นเฉพาะข้อมูลที่ต้องโชว์บนหน้าเว็บ
2. **เขียน**: anon เขียนไม่ได้เลย — ผู้ใช้เขียนได้เฉพาะแถวของตัวเอง
3. **สิทธิ์แอดมิน**: ผ่าน Edge Function + `x-admin-key` เท่านั้น (service_role ไม่เคยอยู่ในเบราว์เซอร์)

---

## D — DO (สิ่งที่ทำไปแล้ว)

| วันที่ | ตาราง/ระบบ | มาตรการ |
|---|---|---|
| ก.ค. 69 | `users` | เปิด RLS — อ่าน/แก้ได้เฉพาะแถวตัวเอง |
| ก.ค. 69 | `bookings` | เปิด RLS — ลูกค้าเห็นเฉพาะการจองตัวเอง, ผู้จัดเห็นเฉพาะทริปตัวเอง |
| ก.ค. 69 | `slips` (storage) | bucket **private** เปิดผ่าน signed URL 1 ชม. เท่านั้น |
| ก.ค. 69 | `payment_reviews` | เปิด RLS แบบไม่มี policy = client เข้าไม่ได้เลย |
| ก.ค. 69 | `trips` | เขียนผ่าน Edge Function `update_trip` เท่านั้น |
| ก.ค. 69 | `organizers` | **Phase 7** — RLS + column GRANT + RPC (ดูล่าง) |
| ก.ค. 69 | Admin ops | ทุกการเขียนผ่าน Edge Function + `x-admin-key` |

### Phase 7 (ล่าสุด) — `organizers`
- anon อ่านได้แค่: `org_name, province, badge_tier, payment_qr_url, status, bio, exp_years, note`
- anon **เขียนไม่ได้เลย**
- ผู้จัดแก้ได้เฉพาะแถวตัวเอง และ **ห้ามแตะ `status` / `badge_tier`** (กันอนุมัติตัวเอง)
- ผู้จัดอ่านข้อมูลเต็มของตัวเองผ่าน `get_my_organizer()` (SECURITY DEFINER)
- ส่งใบสมัครใหม่ผ่าน `organizer_resubmit()` เท่านั้น
- Admin เห็น/แก้ครบผ่าน Edge Function `list_organizers` / `update_organizer`

---

## C — CHECK (ตรวจซ้ำเป็นรอบ)

### สคริปต์ตรวจด่วน (รันได้ทุกครั้งหลัง deploy)
```bash
K="<anon key>"; U="https://<project>.supabase.co/rest/v1"

# 1) anon ต้องอ่าน PII ไม่ได้  → คาดหวัง: permission denied / คอลัมน์ไม่มา
curl -s "$U/organizers?select=id_card,bank_account" -H "apikey: $K" -H "Authorization: Bearer $K"

# 2) anon ต้องเขียนไม่ได้      → คาดหวัง: 401/403 หรือ 0 แถว
curl -s -X PATCH "$U/organ