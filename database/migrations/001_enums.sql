-- Migration 001: ENUM Types
-- Run this FIRST before all other migrations

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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
