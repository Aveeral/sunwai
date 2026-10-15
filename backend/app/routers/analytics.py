"""Administrator dashboard. The analytics views return only aggregates,
and RLS hides sensitive complaints from this role entirely."""
from fastapi import APIRouter, Depends

from ..auth import User, current_user
from ..db import fetch_all, fetch_one, session

router = APIRouter(prefix="/api", tags=["analytics"])


@router.get("/analytics")
def analytics(user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        return {
            "summary": fetch_one(cur, "SELECT * FROM v_dashboard_summary"),
            "weekly_trend": fetch_all(cur, "SELECT * FROM v_weekly_trend ORDER BY week, domain"),
            "hotspots": fetch_all(cur, "SELECT * FROM v_hotspots ORDER BY complaints DESC LIMIT 10"),
            "by_office": fetch_all(cur, "SELECT * FROM v_resolution_by_office ORDER BY complaints DESC"),
            "sla_breaches": fetch_all(cur, "SELECT * FROM v_sla_breaches ORDER BY breach_pct DESC NULLS LAST"),
            "ai_accuracy": fetch_all(cur, "SELECT * FROM v_ai_accuracy ORDER BY triaged DESC"),
            "clarifications": fetch_all(cur, "SELECT * FROM v_clarification_stats ORDER BY pct DESC NULLS LAST"),
        }


@router.get("/admin/complaints")
def all_complaints(user: User = Depends(current_user)):
    """The admin's list: every NON-sensitive complaint (RLS removes the rest)."""
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """SELECT complaint_id, category, domain, status, priority, unit,
                                        filed_at, assigned_person, assigned_committee, deadline_state
                                 FROM v_complaint_overview ORDER BY filed_at DESC LIMIT 200""")


@router.get("/admin/access-log")
def access_log(user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """SELECT log_id, complaint_id, person_name(accessed_by) AS accessed_by,
                                        db_role, action, accessed_at
                                 FROM access_log ORDER BY log_id DESC LIMIT 100""")
