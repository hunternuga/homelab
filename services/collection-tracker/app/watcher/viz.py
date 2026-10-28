"""Scrapes a Viz Media series page for the highest available/orderable
volume number.

This is a page scrape, not an API — Viz has no public feed for new volume
releases. It will need selector/regex maintenance if Viz changes their
site markup. Confirmed working pattern as of 2026-09: volume links look
like `/manga-books/manga/<slug>-volume-<N>/product/<id>`, and "Order now"
/ "Pre-Order" / "Series Debut!" badge text marks a volume as available or
announced (both count as "worth notifying about" per the user's ask).
"""

import logging
import re

import httpx

logger = logging.getLogger(__name__)

VOLUME_LINK_RE = re.compile(r"/manga-books/manga/([a-z0-9-]+)-volume-(\d+)/product/")


def highest_known_volume(slug: str) -> int | None:
    url = f"https://www.viz.com/{slug}"
    resp = httpx.get(url, timeout=15, follow_redirects=True)
    resp.raise_for_status()

    volumes = [
        int(match.group(2))
        for match in VOLUME_LINK_RE.finditer(resp.text)
        if match.group(1) == slug
    ]
    if not volumes:
        logger.warning("No volume links found on %s — page structure may have changed", url)
        return None

    return max(volumes)
