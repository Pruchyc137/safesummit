-- Migration 008: reviews table

CREATE TABLE IF NOT EXISTS reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id),
  trip_id     UUID NOT NULL REFERENCES trips(id),
  rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  is_visible  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(booking_id)    -- 1 การจอง = 1 รีวิว เท่านั้น
);

CREATE INDEX idx_reviews_trip ON reviews(trip_id);

-- trigger: sync rating_avg ใน trips อัตโนมัติ
CREATE TRIGGER trg_review_rating
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_trip_rating();

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- ทุกคนดูรีวิวที่ visible ได้
CREATE POLICY "public view visible reviews"
  ON reviews FOR SELECT USING (is_visible = TRUE);

-- ลูกค้าเขียนรีวิวของตัวเองได้ (เฉพาะ booking ที่ confirmed + trip completed)
CREATE POLICY "users insert own review"
  ON reviews FOR INSERT
  WITH CHECK (
    auth.uid() = user_id AND
    booking_id IN (
      SELECT b.id FROM bookings b
      JOIN trips t ON t.id = b.trip_id
      WHERE b.user_id = auth.uid()
        AND b.status = 'confirmed'
        AND t.status = 'completed'
    )
  );

-- admin ซ่อน/แสดงรีวิวได้
CREATE POLICY "admin manages reviews"
  ON reviews FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));
