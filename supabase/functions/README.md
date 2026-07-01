# SafeSummit — Secure Admin API (Edge Function)

`admin-customers` ให้หน้า Admin อ่าน/อนุมัติลูกค้าได้อย่างปลอดภัย โดยใช้ `service_role`
key ฝั่ง server แทนการเปิด `users` ให้ anon อ่าน (ซึ่งทำให้เลขบัตร ปชช. หลุด)

## ขั้นตอน deploy (ทำครั้งเดียว)

ติดตั้ง Supabase CLI ก่อน: https://supabase.com/docs/guides/cli

```bash
# 1. login + link เข้า project
supabase login
supabase link --project-ref wucrvtgpjqjxxqarzcpv

# 2. ตั้งรหัสลับของ admin (ตั้งเองให้ยาว/เดายาก)
supabase secrets set ADMIN_API_KEY=CHANGE_ME_ยาวๆหน่อย

# 3. deploy (--no-verify-jwt เพราะเราเช็ค x-admin-key เอง)
supabase functions deploy admin-customers --no-verify-jwt
```

Endpoint จะได้:
`https://wucrvtgpjqjxxqarzcpv.supabase.co/functions/v1/admin-customers`

## ทดสอบว่า deploy สำเร็จ

```bash
curl -X POST \
  https://wucrvtgpjqjxxqarzcpv.supabase.co/functions/v1/admin-customers \
  -H "Content-Type: application/json" \
  -H "x-admin-key: <ADMIN_API_KEY ที่ตั้งไว้>" \
  -d '{"action":"list"}'
```
ควรได้ JSON `{"customers":[...]}` กลับมา (ถ้ารหัสผิดจะได้ 401 unauthorized)

## หลัง deploy สำเร็จ

1. บอกทีมพัฒนา (หรือแจ้งกลับมา) เพื่อแก้ `admin.html` ให้เรียก Edge Function นี้แทน
   การ query `users` ตรงๆ — จะส่ง `x-admin-key` ที่ admin กรอกตอน login
2. เมื่อ admin.html ใช้ function แล้ว ให้**ลบ policy ที่เปิดกว้าง**ออก เพื่อปิดช่องโหว่:
   ```sql
   DROP POLICY IF EXISTS "admin_read_users"   ON users;
   DROP POLICY IF EXISTS "admin_update_users" ON users;
   ```
   (เหลือแค่ policy self-only: insert/read/update ของตัวเอง)

## Actions ที่รองรับ
| body | ผลลัพธ์ |
|---|---|
| `{"action":"list"}` | รายชื่อลูกค้าทั้งหมด (role=customer) |
| `{"action":"approve","id":"<uuid>"}` | อนุมัติลูกค้า (status=approved) |
| `{"action":"suspend","id":"<uuid>"}` | ระงับบัญชี (status=suspended) |
