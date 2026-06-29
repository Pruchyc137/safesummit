-- Migration 006: bookings table

CREATE TABLE IF NOT EXISTS bookings (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id),
  trip_id         UUID NOT NULL REFERENCES trips(id),
  booking_ref     VARCHAR(30) UNIQUE NOT NULL,   -- SS-2607-XXX
  seats           INT NOT NULL DEFAULT 1 CHECK (seats >= 1),
  price_snapshot  NUMERIC(10,2) NOT NULL,         -- ราคา ณ วันที่จอง
  total_price     NUMERIC(10,2) NOT NULL,
  status          booking_status NOT NULL DEFAULT 'pending',
  pay_status      pay_status NOT NULL DEFAULT 'unpaid',
  note            TEXT,
  booked_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  confirmed_at    TIMESTAMP,
  cancelled_at    TIMESTAMP,
  cancel_reason   TEXT
);

CREATE INDEX idx_bookings_user ON bookings(user_id);
CREATE INDEX idx_bookings_trip ON bookings(trip_id);
CREATE INDEX idx_bookings_ref  ON bookings(booking_ref);

-- trigger: sync booked_count ใน trips อัตโนมัติ
CREATE TRIGGER trg_booking_count
  AFTER INSERT OR UPDATE OR DELETE ON bookings
  FOR EACH ROW EXECUTE FUNCTION update_trip_booked_count();

ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users view own bookings"
  ON bookings FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "users insert own bookings"
  ON bookings FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users cancel own bookings"
  ON bookings FOR UPDATE USING (auth.uid() = user_id);

-- organizer sees bookings for their trips
CREATE POLICY "organizers view bookings of own trips"
  ON bookings FOR SELECT
  USING (trip_id IN (
    SELECT t.id FROM trips t
    JOIN organizers o ON o.id = t.organizer_id
    WHERE o.user_id = auth.uid()
  ));
