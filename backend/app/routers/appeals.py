"""Ombudsperson: hears appeals."""
from fastapi import APIRouter, Depends

from ..auth import User, current_user
from ..db import fetch_all, session
from ..schemas import DecideAppealIn

router = APIRouter(prefix="/api/appeals", tags=["appeals"])


@router.get("")
def list_appeals(user: User = Depends(current_user)):
    """Row-level security: the Ombudsperson sees the appeals they hear;
    a student sees only their own."""
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """
            SELECT a.appeal_id, a.complaint_id, a.filed_on, a.grounds, a.status, a.outcome,
                   o.category, o.resolution_outcome, o.resolution_note, o.assigned_person,
                   o.assigned_committee
            FROM appeal a JOIN v_complaint_overview o USING (complaint_id)
            ORDER BY (a.status = 'Pending') DESC, a.filed_on DESC""")


@router.post("/{appeal_id}/decide")
def decide(appeal_id: int, body: DecideAppealIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        cur.execute("SELECT decide_appeal(%s::int, %s::text, %s::text)", (appeal_id, body.status, body.outcome))
    return {"result": body.status}
