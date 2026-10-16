"""Demo helpers for the viva.

* clock: move "now" forward so deadlines pass and escalation can be shown
  live. Only app_now() in the database sees this; it changes no data.
* escalate: run the escalation job immediately instead of waiting.
* try-access: run a FIXED forbidden query as the logged-in role and show
  the exact error PostgreSQL gives. The query list is fixed (no user SQL),
  and everything is rolled back.
"""
from fastapi import APIRouter, Depends, HTTPException
from psycopg import errors

from ..auth import User, current_user
from ..db import clock_offset, demo_now, session, set_clock_offset
from ..schemas import ClockIn, TryAccessIn
from ..services import scheduler

router = APIRouter(prefix="/api/demo", tags=["demo"])

ATTEMPTS = {
    "read_all_complaints": (
        "Read every complaint in the table",
        "SELECT count(*) AS rows_visible FROM complaint"),
    "read_icc_cases": (
        "Open the ICC's confidential case list",
        "SELECT complaint_id, category, status FROM v_icc_cases"),
    "read_identity": (
        "See who filed each complaint",
        "SELECT complaint_id, person_id FROM complainant_identity"),
    "read_phone_numbers": (
        "Read everyone's phone number",
        "SELECT person_id, first_name, phone FROM person LIMIT 5"),
    "edit_description": (
        "Rewrite what the student wrote in a complaint",
        "UPDATE complaint SET description = 'edited' "
        "WHERE complaint_id = (SELECT min(complaint_id) FROM complaint)"),
    "change_priority": (
        "Lower a complaint's priority",
        "UPDATE complaint SET priority = 'Low' "
        "WHERE complaint_id = (SELECT min(complaint_id) FROM complaint)"),
    "delete_history": (
        "Delete a complaint's status history",
        "DELETE FROM status_history WHERE complaint_id = (SELECT min(complaint_id) FROM complaint)"),
    "delete_access_log": (
        "Erase the audit log",
        "DELETE FROM access_log"),
    "read_access_log": (
        "Read the audit log of who opened confidential cases",
        "SELECT count(*) AS log_rows FROM access_log"),
}


@router.get("/clock")
def get_clock():
    return {"offset_hours": clock_offset(), "now": demo_now().isoformat()}


@router.post("/clock")
def set_clock(body: ClockIn, user: User = Depends(current_user)):
    if body.offset_hours is not None:
        set_clock_offset(body.offset_hours)
    elif body.advance_hours is not None:
        set_clock_offset(clock_offset() + body.advance_hours)
    return get_clock()


@router.post("/escalate")
def escalate_now(user: User = Depends(current_user)):
    return scheduler.run_once()


@router.get("/attempts")
def list_attempts():
    return [{"action": k, "label": v[0], "sql": v[1]} for k, v in ATTEMPTS.items()]


@router.post("/try-access")
def try_access(body: TryAccessIn, user: User = Depends(current_user)):
    if body.action not in ATTEMPTS:
        raise HTTPException(404, "Unknown action")
    label, query = ATTEMPTS[body.action]
    out = {"action": body.action, "label": label, "sql": query, "role": user.role}
    with session(user.person_id, user.role) as cur:
        try:
            with cur.connection.transaction(force_rollback=True):   # never keeps changes
                cur.execute(query)
                out["allowed"] = True
                out["rows"] = cur.fetchall() if cur.description else []
                out["rowcount"] = cur.rowcount
        except errors.InsufficientPrivilege as e:
            out["allowed"] = False
            out["error"] = e.diag.message_primary
        except errors.RaiseException as e:            # trigger refused (append-only)
            out["allowed"] = False
            out["error"] = e.diag.message_primary
    return out
