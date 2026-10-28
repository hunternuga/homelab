import logging
import os

import httpx

logger = logging.getLogger(__name__)


def send_notification(title: str, message: str) -> bool:
    """Send a push notification via Home Assistant's notify service.

    Returns True on success, False on any failure (never raises — a failed
    notification shouldn't crash the watcher run or lose the alert; the
    caller decides whether to mark it notified based on the return value).
    """
    base_url = os.environ["HA_BASE_URL"].rstrip("/")
    service = os.environ["HA_NOTIFY_SERVICE"]
    token = os.environ["HA_TOKEN"]

    url = f"{base_url}/api/services/{service.replace('.', '/', 1)}"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    payload = {"title": title, "message": message}

    try:
        resp = httpx.post(url, json=payload, headers=headers, timeout=10)
        resp.raise_for_status()
        return True
    except httpx.HTTPError:
        logger.exception("Failed to send Home Assistant notification")
        return False
