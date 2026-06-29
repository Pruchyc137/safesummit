-- Migration 009: Seed Data (Development only)
-- WARNING: เปลี่ยน password ก่อน deploy production

-- Admin account
INSERT INTO users (email, password_hash, full_name, role) VALUES
  ('admin@safesummit.co.th', crypt('SafeSummit@2026', gen_salt('bf')), 'SafeSummit Admin', 'admin')
ON CONFLICT (email) DO NOTHING;
