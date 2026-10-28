import re

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from common.db import get_conn
from common.notify import send_notification

app = FastAPI(title="Collection Tracker")
app.mount("/static", StaticFiles(directory="api/static"), name="static")
templates = Jinja2Templates(directory="api/templates")


def _issue_num(issue_number: str) -> int | None:
    digits = re.sub(r"\D", "", issue_number)
    return int(digits) if digits else None


@app.get("/", response_class=HTMLResponse)
def dashboard(request: Request):
    with get_conn() as conn:
        series_rows = conn.execute(
            "SELECT id, name, kind, display_mode FROM series ORDER BY name"
        ).fetchall()

        series_list = []
        for series in series_rows:
            items = conn.execute(
                "SELECT id, issue_number, display_name, status, target_price, notes "
                "FROM items WHERE series_id = %s ORDER BY issue_number",
                (series["id"],),
            ).fetchall()

            grid = None
            if series["display_mode"] == "completionist":
                owned_nums = {
                    n for it in items if it["status"] == "owned"
                    and (n := _issue_num(it["issue_number"])) is not None
                }
                highest = max(owned_nums, default=0)
                grid = [
                    {"number": n, "owned": n in owned_nums}
                    for n in range(1, highest + 1)
                ]

            series_list.append({**series, "entries": items, "grid": grid})

    return templates.TemplateResponse(
        "dashboard.html", {"request": request, "series_list": series_list}
    )


@app.get("/items/{item_id}/history", response_class=HTMLResponse)
def item_history(request: Request, item_id: int):
    with get_conn() as conn:
        item = conn.execute(
            "SELECT items.*, series.name AS series_name FROM items "
            "JOIN series ON series.id = items.series_id WHERE items.id = %s",
            (item_id,),
        ).fetchone()
        if item is None:
            raise HTTPException(status_code=404, detail="Item not found")

        history = conn.execute(
            "SELECT price, currency, source, listing_url, checked_at "
            "FROM price_history WHERE item_id = %s ORDER BY checked_at DESC",
            (item_id,),
        ).fetchall()

    return templates.TemplateResponse(
        "history.html", {"request": request, "item": item, "history": history}
    )


@app.get("/alerts", response_class=HTMLResponse)
def alerts(request: Request):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT alerts.*, series.name AS series_name FROM alerts "
            "LEFT JOIN series ON series.id = alerts.series_id "
            "ORDER BY created_at DESC LIMIT 100"
        ).fetchall()

    return templates.TemplateResponse("alerts.html", {"request": request, "alerts": rows})


@app.post("/test-alert")
def test_alert():
    ok = send_notification(
        "Collection Tracker test", "This is a manual test notification."
    )
    if not ok:
        raise HTTPException(status_code=502, detail="Notification failed — check logs")
    return {"status": "sent"}
