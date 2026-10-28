import logging

from common.db import get_conn
from common.notify import send_notification
from watcher import ebay, viz

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _maybe_alert(conn, *, item_id, series_id, kind, detail, dedupe_key, title):
    """Insert an alert if its dedupe_key is new, and notify on success.

    Returns True if a new alert was inserted (regardless of whether the
    notification itself succeeded — a failed push shouldn't cause the same
    alert to be re-inserted and re-attempted forever on every run).
    """
    row = conn.execute(
        """
        INSERT INTO alerts (item_id, series_id, kind, detail, dedupe_key)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (dedupe_key) DO NOTHING
        RETURNING id
        """,
        (item_id, series_id, kind, detail, dedupe_key),
    ).fetchone()

    if row is None:
        return False

    if send_notification(title, detail):
        conn.execute(
            "UPDATE alerts SET notified_at = now() WHERE id = %s", (row["id"],)
        )
    return True


def check_viz_releases(conn):
    series_rows = conn.execute(
        "SELECT id, name, viz_slug FROM series WHERE viz_slug IS NOT NULL"
    ).fetchall()

    for series in series_rows:
        try:
            latest = viz.highest_known_volume(series["viz_slug"])
        except Exception:
            logger.exception("Viz check failed for series %s", series["name"])
            continue

        if latest is None:
            continue

        owned = conn.execute(
            """
            SELECT MAX(NULLIF(regexp_replace(issue_number, '\\D', '', 'g'), '')::int) AS max_num
            FROM items WHERE series_id = %s
            """,
            (series["id"],),
        ).fetchone()
        max_owned = owned["max_num"] or 0

        if latest > max_owned:
            _maybe_alert(
                conn,
                item_id=None,
                series_id=series["id"],
                kind="new_release",
                detail=f"{series['name']} Vol. {latest} is now listed on Viz",
                dedupe_key=f"new_release:series:{series['id']}:vol:{latest}",
                title=f"New {series['name']} volume",
            )


def check_ebay_prices(conn):
    wanted = conn.execute(
        "SELECT id, series_id, display_name, issue_number, ebay_query, target_price "
        "FROM items WHERE status = 'wanted' AND ebay_query IS NOT NULL"
    ).fetchall()

    if not wanted:
        return

    try:
        token = ebay.get_access_token()
    except Exception:
        logger.exception("Failed to obtain eBay access token")
        return

    for item in wanted:
        try:
            result = ebay.find_lowest_price(token, item["ebay_query"])
        except Exception:
            logger.exception("eBay search failed for item %s", item["id"])
            continue

        if result is None:
            continue

        conn.execute(
            """
            INSERT INTO price_history (item_id, price, currency, source, listing_url)
            VALUES (%s, %s, %s, 'ebay', %s)
            """,
            (item["id"], result["price"], result["currency"], result["listing_url"]),
        )

        label = item["display_name"] or item["issue_number"]
        target = item["target_price"]
        if target is not None and result["price"] <= float(target):
            _maybe_alert(
                conn,
                item_id=item["id"],
                series_id=item["series_id"],
                kind="price_drop",
                detail=f"{label} found for ${result['price']:.2f} (target ${target})",
                dedupe_key=f"price_drop:item:{item['id']}:{round(result['price'])}",
                title=f"Price drop: {label}",
            )


def main():
    with get_conn() as conn:
        check_viz_releases(conn)
        check_ebay_prices(conn)
    logger.info("Watcher run complete")


if __name__ == "__main__":
    main()
