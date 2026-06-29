-- Migration 003: organizers table

CREATE TABLE IF NOT EXISTS organizers (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  org_name      VARCHAR(255) NOT NULL,
  bio           TEXT,
  province      VARCHAR(100),
  exp_years     INT DEFAULT 0,
  badge_tier    badge_tier NOT NULL DEFAULT 'unverified',
  status        org_status NOT NULL DEFAULT 'pending',
  reg_ref       VARCHAR(50) UNIQUE,
  approved_by   UUID REFERENCES users(id),
  approved_at   TIMESTAMP,
  suspended_at  TIMESTAMP,
  note          TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

ALTER TABLE organizers ENABLE ROW LEVEL SECURITY;

-- organizer can view own record
CREATE POLICY "organizers view own record"
  ON organizers FOR SELECT USING (user_id = auth.uid());

-- admin can view all
CREATE POLICY "admin views all organizers"
  ON organizers FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- anyone can insert (registration)
CREATE POLICY "anyone can register as organizer"
  ON organizers FOR INSERT WITH CHECK (user_id = auth.uid());
