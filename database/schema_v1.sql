-- ============================================================
-- SafeSummit — Database Schema v1
-- Platform: Supabase (PostgreSQL 15)
-- Created: 2026-06-27
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- ENUM TYPES
-- ============================================================

CREATE TYPE user_role        AS ENUM ('customer', 'organizer', 'admin');
CREATE TYPE org_status       AS ENUM ('pending', 'approved', 'suspended');
CREATE TYPE badge_tier       AS ENUM ('unverified', 'basic', 'pro');
CREATE TYPE trip_region      AS ENUM ('north', 'northeast', 'central', 'east', 'west', 'south');
CREATE TYPE trip_status      AS ENUM ('draft', 'open', 'full', 'ongoing', 'completed', 'cancelled');
CREATE TYPE trip_difficulty  AS ENUM ('easy', 'medium', 'hard', 'expert');
CREATE TYPE booking_status   AS ENUM ('pending', 'confirmed', 'cancelled');
CREATE TYPE pay_status       AS ENUM ('unpaid', 'paid', 'refunded');
CREATE TYPE payment_method   AS ENUM ('promptpay', 'bank_transfer', 'credit_card');
CREATE TYPE payment_status   AS ENUM ('pending', 'verified', 'failed');

-- ============================================================
-- TABLE: users
-- ทุกคนในระบบ — ลูกค้า, ผู้จัด, admin
-- ============================================================

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name     VARCHAR(255) NOT NULL,
  phone         VARCHAR(20),
  role          user_role NOT NULL DEFAULT 'customer',
  avatar_url    TEXT,
  verified_at   TIMESTAMP,
  created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE: organizers
-- ข้อมูลเพิ่มเติมของผู้จัดทริป (1:1 กับ users)
-- ============================================================

CREATE TABLE organizers (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  org_name      VARCHAR(255) NOT NULL,
  bio           TEXT,
  province      VARCHAR(100),
  exp_years     INT DEFAULT 0,
  badge_tier    badge_tier NOT NULL DEFAULT 'unverified',
  status        org_status NOT NULL DEFAULT 'pending',
  reg_ref       VARCHAR(50) UNIQUE,           -- เลขอ้างอิงการสมัคร เช่น ORG-ABC123
  approved_by   UUID REFERENCES users(id),   -- admin ที่อนุมัติ
  approved_at   TIMESTAMP,
  suspended_at  TIMESTAMP,
  note          TEXT,                         -- หมายเหตุจาก admin
  created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

-- ============================================================
-- TABLE: trips
-- ทริปทั้งหมดในระบบ
-- ============================================================

CREATE TABLE trips (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organizer_id      UUID NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  name_th           VARCHAR(255) NOT NULL,
  name_en           VARCHAR(255),
  description       TEXT,
  region            trip_region NOT NULL,
  province          VARCHAR(100) NOT NULL,
  start_date        DATE NOT NULL,
  duration_days     INT NOT NULL DEFAULT 1,
  price_per_person  NUMERIC(10,2) NOT NULL CHECK (price_per_person >= 0),
  capacity          INT NOT NULL CHECK (capacity >= 1),
  booked_count      INT NOT NULL DEFAULT 0 CHECK (booked_count >= 0),
  status            trip_status NOT NULL DEFAULT 'draft',
  badge_tier        badge_tier NOT NULL DEFAULT 'basic',
  difficulty        trip_difficulty NOT NULL DEFAULT 'medium',
  image_url         TEXT,
  includes          TEXT[],                  -- ['ไกด์นำทาง', 'อาหารทุกมื้อ', ...]
  rating_avg        NUMERIC(3,2) DEFAULT 0,  -- คำนวณจาก reviews
  rating_count      INT DEFAULT 0,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT booked_le_capacity CHECK (booked_count <= capacity)
);

-- ============================================================
-- TABLE: trip_itinerary
-- กำหนดการรายวันของแต่ละทริป
-- ============================================================

CREATE TABLE trip_itinerary (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  day_number      INT NOT NULL CHECK (day_number >= 1),
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  highlights      TEXT[],                    -- ['ยอดดอย', 'จุดชมวิว', ...]
  meal_included   TEXT[],                    -- ['breakfast', 'lunch', 'dinner']
  accommodation   VARCHAR(255),              -- ที่พักคืนนั้น
  UNIQUE(trip_id, day_number)
);

-- ============================================================
-- TABLE: bookings
-- การจองของลูกค้า
-- ============================================================

CREATE TABLE bookings (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id),
  trip_id         UUID NOT NULL REFERENCES trips(id),
  booking_ref     VARCHAR(30) UNIQUE NOT NULL,  -- SS-2607-XXX
  seats           INT NOT NULL DEFAULT 1 CHECK (seats >= 1),
  price_snapshot  NUMERIC(10,2) NOT NULL,        -- ราคา ณ วันที่จอง (กันราคาเปลี่ยน)
  total_price     NUMERIC(10,2) NOT NULL,
  status          booking_status NOT NULL DEFAULT 'pending',
  pay_status      pay_status NOT NULL DEFAULT 'unpaid',
  note            TEXT,                          -- หมายเหตุจากลูกค้า
  booked_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  confirmed_at    TIMESTAMP,
  cancelled_at    TIMESTAMP,
  cancel_reason   TEXT
);

-- ============================================================
-- TABLE: payments
-- หลักฐานการชำระเงิน (1:1 กับ bookings)
-- ============================================================

CREATE TABLE payments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  amount      NUMERIC(10,2) NOT NULL,
  method      payment_method NOT NULL DEFAULT 'promptpay',
  status      payment_status NOT NULL DEFAULT 'pending',
  slip_url    TEXT,                          -- URL รูปสลิปที่อัปโหลด
  ref_code    VARCHAR(100),                  -- รหัสอ้างอิงจากธนาคาร
  paid_at     TIMESTAMP,
  verified_by UUID REFERENCES users(id),    -- admin ที่ verify
  verified_at TIMESTAMP,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(booking_id)
);

-- ============================================================
-- TABLE: reviews
-- รีวิวหลังทริปจบ (เขียนได้เฉพาะคนที่จองและทริปจบแล้ว)
-- ============================================================

CREATE TABLE reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id),
  trip_id     UUID NOT NULL REFERENCES trips(id),
  rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  is_visible  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(booking_id)                         -- 1 การจอง = 1 รีวิว
);

-- ============================================================
-- INDEXES (performance)
-- ============================================================

CREATE INDEX idx_trips_region       ON trips(region);
CREATE INDEX idx_trips_status       ON trips(status);
CREATE INDEX idx_trips_start_date   ON trips(start_date);
CREATE INDEX idx_trips_organizer    ON trips(organizer_id);
CREATE INDEX idx_bookings_user      ON bookings(user_id);
CREATE INDEX idx_bookings_trip      ON bookings(trip_id);
CREATE INDEX idx_bookings_ref       ON bookings(booking_ref);
CREATE INDEX idx_reviews_trip       ON reviews(trip_id);

-- ============================================================
-- TRIGGERS
-- ============================================================

-- อัปเดต updated_at อัตโนมัติ
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_trips_updated
  BEFORE UPDATE ON trips
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- อัปเดต booked_count และ rating_avg อัตโนมัติ
CREATE OR REPLACE FUNCTION update_trip_booked_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE trips SET booked_count = (
    SELECT COALESCE(SUM(seats), 0) FROM bookings
    WHERE trip_id = NEW.trip_id AND status != 'cancelled'
  ) WHERE id = NEW.trip_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_count
  AFTER INSERT OR UPDATE OR DELETE ON bookings
  FOR EACH ROW EXECUTE FUNCTION update_trip_booked_count();

CREATE OR REPLACE FUNCTION update_trip_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE trips SET
    rating_avg   = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM reviews WHERE trip_id = NEW.trip_id AND is_visible = TRUE),
    rating_count = (SELECT COUNT(*) FROM reviews WHERE trip_id = NEW.trip_id AND is_visible = TRUE)
  WHERE id = NEW.trip_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_review_rating
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_trip_rating();

-- ============================================================
-- ROW LEVEL SECURITY (Supabase RLS)
-- ============================================================

ALTER TABLE users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips          ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_itinerary ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews        ENABLE ROW LEVEL SECURITY;

-- ลูกค้า: ดูทริปที่เปิดอยู่ได้
CREATE POLICY "public can view open trips"
  ON trips FOR SELECT
  USING (status IN ('open', 'full', 'ongoing', 'completed'));

-- ลูกค้า: ดูเฉพาะการจองของตัวเอง
CREATE POLICY "users see own bookings"
  ON bookings FOR SELECT
  USING (auth.uid() = user_id);

-- ลูกค้า: จองได้เฉพาะตัวเอง
CREATE POLICY "users insert own bookings"
  ON bookings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ผู้จัด: จัดการทริปของตัวเอง
CREATE POLICY "organizers manage own trips"
  ON trips FOR ALL
  USING (organizer_id IN (
    SELECT id FROM organizers WHERE user_id = auth.uid()
  ));

-- ทุกคน: ดูรีวิวที่ visible ได้
CREATE POLICY "public can view visible reviews"
  ON reviews FOR SELECT
  USING (is_visible = TRUE);

-- ============================================================
-- SEED DATA (ตัวอย่าง)
-- ============================================================

-- Admin account (password: admin1234 — เปลี่ยนก่อน deploy)
INSERT INTO users (email, password_hash, full_name, role) VALUES
  ('admin@safesummit.co.th', 'CHANGE_THIS_HASH', 'SafeSummit Admin', 'admin');
