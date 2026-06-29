-- Migration 004: trips table

CREATE TABLE IF NOT EXISTS trips (
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
  includes          TEXT[],
  rating_avg        NUMERIC(3,2) DEFAULT 0,
  rating_count      INT DEFAULT 0,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT booked_le_capacity CHECK (booked_count <= capacity)
);

-- Indexes
CREATE INDEX idx_trips_region     ON trips(region);
CREATE INDEX idx_trips_status     ON trips(status);
CREATE INDEX idx_trips_start_date ON trips(start_date);
CREATE INDEX idx_trips_organizer  ON trips(organizer_id);

-- auto updated_at
CREATE TRIGGER trg_trips_updated
  BEFORE UPDATE ON trips
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- auto update booked_count from bookings
CREATE OR REPLACE FUNCTION update_trip_booked_count()
RETURNS TRIGGER AS $$
DECLARE affected_trip UUID;
BEGIN
  affected_trip := COALESCE(NEW.trip_id, OLD.trip_id);
  UPDATE trips SET booked_count = (
    SELECT COALESCE(SUM(seats), 0) FROM bookings
    WHERE trip_id = affected_trip AND status != 'cancelled'
  ) WHERE id = affected_trip;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- auto update rating_avg from reviews
CREATE OR REPLACE FUNCTION update_trip_rating()
RETURNS TRIGGER AS $$
DECLARE affected_trip UUID;
BEGIN
  affected_trip := COALESCE(NEW.trip_id, OLD.trip_id);
  UPDATE trips SET
    rating_avg   = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM reviews WHERE trip_id = affected_trip AND is_visible = TRUE),
    rating_count = (SELECT COUNT(*) FROM reviews WHERE trip_id = affected_trip AND is_visible = TRUE)
  WHERE id = affected_trip;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;

-- public can see open/ongoing/completed trips
CREATE POLICY "public view open trips"
  ON trips FOR SELECT
  USING (status IN ('open', 'full', 'ongoing', 'completed'));

-- organizer manages own trips
CREATE POLICY "organizers manage own trips"
  ON trips FOR ALL
  USING (organizer_id IN (
    SELECT id FROM organizers WHERE user_id = auth.uid()
  ));
