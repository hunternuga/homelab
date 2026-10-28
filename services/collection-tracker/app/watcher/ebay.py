import logging
import os

import httpx

logger = logging.getLogger(__name__)

TOKEN_URL = "https://api.ebay.com/identity/v1/oauth2/token"
SEARCH_URL = "https://api.ebay.com/buy/browse/v1/item_summary/search"


def get_access_token() -> str:
    """Fetch a fresh OAuth app token.

    Not cached/persisted — at once-a-day CronJob volume, one token request
    per run is nowhere near eBay's 1000/day limit, so persistence isn't
    worth the complexity.
    """
    client_id = os.environ["EBAY_CLIENT_ID"]
    client_secret = os.environ["EBAY_CLIENT_SECRET"]

    resp = httpx.post(
        TOKEN_URL,
        auth=(client_id, client_secret),
        data={
            "grant_type": "client_credentials",
            "scope": "https://api.ebay.com/oauth/api_scope",
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def find_lowest_price(token: str, query: str) -> dict | None:
    """Return the lowest-priced active listing for a search query, or None."""
    resp = httpx.get(
        SEARCH_URL,
        params={"q": query, "sort": "price", "limit": 10},
        headers={
            "Authorization": f"Bearer {token}",
            "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
        },
        timeout=10,
    )
    resp.raise_for_status()
    items = resp.json().get("itemSummaries") or []
    if not items:
        return None

    cheapest = items[0]
    price = cheapest.get("price", {})
    return {
        "price": float(price["value"]),
        "currency": price.get("currency", "USD"),
        "listing_url": cheapest.get("itemWebUrl"),
    }
