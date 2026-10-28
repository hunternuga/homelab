DO $$ BEGIN
    CREATE TYPE item_status AS ENUM ('owned', 'wanted', 'not_for_sale');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS series (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    kind          TEXT NOT NULL,
    -- 'completionist' series show an owned/missing grid (every volume up to
    -- the latest release "should" be owned); 'curated' series just list
    -- owned + wanted items with no implied gaps (specific issues chosen on
    -- purpose, not a run to complete).
    display_mode  TEXT NOT NULL DEFAULT 'curated',
    viz_slug      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS items (
    id            SERIAL PRIMARY KEY,
    series_id     INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    issue_number  TEXT NOT NULL,
    display_name  TEXT,
    status        item_status NOT NULL,
    target_price  NUMERIC(10, 2),
    owned_at      DATE,
    notes         TEXT,
    ebay_query    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (series_id, issue_number)
);

CREATE TABLE IF NOT EXISTS price_history (
    id           SERIAL PRIMARY KEY,
    item_id      INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    price        NUMERIC(10, 2) NOT NULL,
    currency     TEXT NOT NULL DEFAULT 'USD',
    source       TEXT NOT NULL DEFAULT 'ebay',
    listing_url  TEXT,
    checked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_price_history_item_checked
    ON price_history (item_id, checked_at DESC);

CREATE TABLE IF NOT EXISTS alerts (
    id           SERIAL PRIMARY KEY,
    item_id      INTEGER REFERENCES items(id) ON DELETE CASCADE,
    series_id    INTEGER REFERENCES series(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL,
    detail       TEXT NOT NULL,
    dedupe_key   TEXT NOT NULL UNIQUE,
    notified_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
