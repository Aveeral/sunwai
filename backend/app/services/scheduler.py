"""Background job: every few minutes, ask the database to escalate overdue
complaints and close ones that waited too long for the complainant.
All the logic is in the procedures; this only calls them."""
import asyncio
import logging

from ..config import settings
from ..db import scalar, system_session

log = logging.getLogger("sunwai.scheduler")


def run_once() -> dict:
    with system_session() as cur:
        escalated = scalar(cur, "SELECT escalate_overdue()")
        closed = scalar(cur, "SELECT close_stale_needs_info(7)")
    if escalated or closed:
        log.info("scheduler: escalated %s, closed %s", escalated, closed)
    return {"escalated": escalated, "closed_stale": closed}


async def loop():
    while True:
        await asyncio.sleep(settings.scheduler_seconds)
        try:
            await asyncio.to_thread(run_once)
        except Exception:                      # keep the loop alive
            log.exception("scheduler run failed")
