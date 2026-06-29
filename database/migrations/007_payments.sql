-- Migration 007: payments table

CREATE TABLE IF NOT EXISTS payments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  amount      NUMERIC(10,2) NOT NULL,
  method      payment_method NOT NULL DEFAULT 'promptpay',
  status      payment_status NOT NULL DEFAULT 'pending',
  slip_url    TEXT,             -- URL รูปสลิปใน Supabase Storage
  ref_code    VARCHAR(100),     -- รหัสอ้างอิงจากธนาคาร
  paid_at     TIMESTAMP,
  verified_by UUID REFERENCES users(id),
  verified_at TIMESTAMP,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(booking_id)
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- users see own payment
CREATE POLICY "users view own payment"
  ON payments FOR SELECT
  USING (booking_id IN (
    SELECT id FROM bookings WHERE user_id = auth.uid()
  ));

-- users can insert payment (upload slip)
CREATE POLICY "users insert own payment"
  ON payments FOR INSERT
  WITH CHECK (booking_id IN (
    SELECT id FROM bookings WHERE user_id = auth.uid()
  ));

-- admin verifies payment
CREATE POLICY "admin manages payments"
  ON payments FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));
