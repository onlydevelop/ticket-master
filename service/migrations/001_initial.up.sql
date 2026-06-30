CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE venues (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    city        TEXT NOT NULL,
    country     TEXT NOT NULL,
    capacity    INT  NOT NULL
);

CREATE TABLE performers (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL
);

CREATE TABLE events (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id     UUID        NOT NULL REFERENCES venues(id),
    title        TEXT        NOT NULL,
    description  TEXT        NOT NULL DEFAULT '',
    starts_at    TIMESTAMPTZ NOT NULL,
    -- tsvector for full-text search across title and description
    search_vector TSVECTOR   GENERATED ALWAYS AS (
        to_tsvector('english', title || ' ' || description)
    ) STORED
);

-- GIN index enables fast full-text search without Elasticsearch
CREATE INDEX events_search_idx ON events USING GIN (search_vector);

CREATE TABLE event_performers (
    event_id     UUID NOT NULL REFERENCES events(id)     ON DELETE CASCADE,
    performer_id UUID NOT NULL REFERENCES performers(id) ON DELETE CASCADE,
    PRIMARY KEY (event_id, performer_id)
);

CREATE TABLE tickets (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID        NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    section     TEXT        NOT NULL,
    row         TEXT        NOT NULL,
    seat        TEXT        NOT NULL,
    price_cents INT         NOT NULL,
    -- status + expiration pattern: the core of the no-double-booking guarantee
    status      TEXT        NOT NULL DEFAULT 'available'
                            CHECK (status IN ('available', 'reserved', 'booked')),
    reserved_by UUID,
    expires_at  TIMESTAMPTZ
);

CREATE INDEX tickets_event_status_idx ON tickets (event_id, status);

CREATE TABLE bookings (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id   UUID        NOT NULL REFERENCES tickets(id),
    user_id     UUID        NOT NULL,
    status      TEXT        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
