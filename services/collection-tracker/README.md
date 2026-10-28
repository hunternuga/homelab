# Collection Tracker

Personal collection tracker for Kagurabachi manga and Web of Spider-Man
comics — owned/wanted inventory, eBay price watching, and Viz new-release
alerts, with push notifications via Home Assistant.

## How it works

- **Postgres** (`app/db/schema.sql`, `app/db/seed.sql`) — `series`,
  `items` (one table for both owned and wanted, distinguished by
  `status`), `price_history`, `alerts`. Applied idempotently via an
  initContainer on every API pod start.
- **Watcher** (`app/watcher/`, runs daily as a CronJob) —
  - `viz.py` scrapes the series' Viz Media page for the highest
    listed/orderable volume number. **This is a page scrape, not an API**
    — Viz has no feed for new releases. If alerts stop firing for a series
    that should have a new volume, check whether Viz changed their page
    markup (`VOLUME_LINK_RE` in `viz.py` is the thing to fix).
  - `ebay.py` searches the eBay Browse API (OAuth Client Credentials —
    active listings only, no sold/completed data exists via any API
    anymore) for each `wanted` item's lowest current price.
  - Alerts are deduplicated via a `dedupe_key` so the same new-release or
    price-drop doesn't re-notify every run; `price_history` still
    accumulates a full row every run regardless.
- **API + dashboard** (`app/api/`) — FastAPI + server-rendered Jinja2,
  no JS framework. A series' `display_mode` controls how it's shown:
  `completionist` (Kagurabachi) renders an owned/missing volume grid;
  `curated` (Web of Spider-Man) renders a plain list with no implied gaps,
  since those specific issues were chosen on purpose, not a run to
  complete.

## Adding a wanted item

No admin UI (single-user, rarely used):

```bash
kubectl exec -it deploy/collection-postgres -n homelab -- psql -U collection -d collection
```

```sql
INSERT INTO items (series_id, issue_number, display_name, status, target_price, ebay_query)
VALUES (
    (SELECT id FROM series WHERE name = 'Web of Spider-Man'),
    '96', 'Web of Spider-Man #96', 'wanted', 25.00, 'web of spider-man 96'
);
```
