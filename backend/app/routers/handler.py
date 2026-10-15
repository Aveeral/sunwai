"""Office handlers (caretaker, warden, HOD, Computer Centre, ...)."""
from fastapi import APIRouter, Depends

from ..auth import User, current_user
from ..db import fetch_all, session

router = APIRouter(prefix="/api/handler", tags=["handler"])


@router.get("/queue")
def queue(user: User = Depends(current_user)):
    """Open complaints assigned to me. A student gets 'permission denied for
    view v_handler_queue' straight from PostgreSQL."""
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """SELECT * FROM v_handler_queue
                                 ORDER BY priority_rank(priority) DESC, due_at""")


@router.get("/history")
def history(user: User = Depends(current_user)):
    """Complaints I handled before (resolved, or escalated away from me)."""
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """
            SELECT complaint_id, category, status, priority, filed_at, resolved_at,
                   resolution_outcome, feedback_rating, assigned_person
            FROM v_complaint_overview
            WHERE was_handler(complaint_id) AND NOT is_current_handler(complaint_id)
               OR (is_current_handler(complaint_id) AND status IN ('Resolved','Closed','Rejected'))
            ORDER BY filed_at DESC LIMIT 50""")
