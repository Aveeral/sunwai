"""Committees: ICC, Anti-Ragging Committee, SGRC.

Each committee role has its own view (v_icc_cases, ...). The ICC role
cannot read the SGRC's view and vice versa: that is plain GRANT."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import User, current_user
from ..db import fetch_all, session

router = APIRouter(prefix="/api/committee", tags=["committee"])

VIEW_FOR_ROLE = {
    "sunwai_icc": "v_icc_cases",
    "sunwai_antiragging": "v_antiragging_cases",
    "sunwai_sgrc": "v_sgrc_cases",
}


@router.get("/cases")
def cases(user: User = Depends(current_user)):
    view = VIEW_FOR_ROLE.get(user.role, "v_committee_cases")
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, f"SELECT * FROM {view} ORDER BY filed_at DESC")


@router.get("/cases/{committee}")
def cases_of(committee: str, user: User = Depends(current_user)):
    """Lets the demo ask for ANOTHER committee's view and get refused by the DB."""
    views = {"icc": "v_icc_cases", "antiragging": "v_antiragging_cases", "sgrc": "v_sgrc_cases"}
    if committee not in views:
        raise HTTPException(404, "Unknown committee")
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, f"SELECT * FROM {views[committee]} ORDER BY filed_at DESC")
