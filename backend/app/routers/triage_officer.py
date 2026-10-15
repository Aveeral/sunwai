"""Triage officer: confirms the category when the AI was not sure."""
from fastapi import APIRouter, Depends

from ..auth import User, current_user
from ..db import fetch_all, scalar, session
from ..schemas import ConfirmTriageIn

router = APIRouter(prefix="/api/triage", tags=["triage officer"])


@router.get("/queue")
def queue(user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, "SELECT * FROM v_triage_queue ORDER BY filed_at")


@router.post("/{cid}/confirm")
def confirm(cid: int, body: ConfirmTriageIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        result = scalar(cur, "SELECT confirm_triage(%s::int, %s::int, %s::text)", (cid, body.category_id, body.priority))
    return {"result": result}
