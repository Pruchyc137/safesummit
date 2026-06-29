-- Migration 005: trip_itinerary table

CREATE TABLE IF NOT EXISTS trip_itinerary (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  day_number      INT NOT NULL CHECK (day_number >= 1),
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  highlights      TEXT[],
  meal_included   TEXT[],        -- ['breakfast','lunch','dinner']
  accommodation   VARCHAR(255),
  UNIQUE(trip_id, day_number)
);

CREATE INDEX idx_itinerary_trip ON trip_itinerary(trip_id);

ALTER TABLE trip_itinerary ENABLE ROW LEVEL SECURITY;

-- public can read itinerary of open trips
CREATE POLICY "public view itinerary of open trips"
  ON trip_itinerary FOR SELECT
  USING (trip_id IN (
    SELECT id FROM trips WHERE status IN ('open','full','ongoing','completed')
  ));

-- organizer manages own trip itinerary
CREATE POLICY "organizers manage own itinerary"
  ON trip_itinerary FOR ALL
  USING (trip_id IN (
    SELECT t.id FROM trips t
    JOIN organizers o ON o.id = t.organizer_id
    WHERE o.user_id = auth.uid()
  ));
