"""Complainant side: file, list, open, answer questions, rate, reopen, appeal."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import User, current_user
from ..db import fetch_all, fetch_one, scalar, session, try_fetch
from ..schemas import AnswerIn, FileIn, PreviewIn, RateIn, StatusIn, TextIn
from ..services import triage

router = APIRouter(prefix="/api", tags=["complaints"])


@router.post("/triage/preview")
def preview(body: PreviewIn, user: User = Depends(current_user)):
    return triage.preview(user, body.description)


@router.post("/complaints")
def file_complaint(body: FileIn, user: User = Depends(current_user)):
    return triage.file(user, body.analysis_id, body.visibility, body.contact_consent,
                       body.details, [p.model_dump() for p in body.people]
                       if body.people is not None else None)


@router.get("/complaints/mine")
def my_complaints(user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, "SELECT * FROM v_my_complaints ORDER BY filed_at DESC")


@router.get("/people/search")
def people_search(q: str, role: str = "Unknown", user: User = Depends(current_user)):
    if len(q.strip()) < 2:
        return []
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, "SELECT * FROM find_person_candidates(%s::text, %s::text)", (q.strip(), role))


@router.get("/complaints/{cid}")
def complaint_page(cid: int, user: User = Depends(current_user)):
    """Everything about one complaint that THIS role may see.

    open_complaint() refuses (403) if the person may not see it at all, and
    writes the access log for confidential cases. Each section is then read
    separately; a section this role has no GRANT for comes back as "hidden",
    and row-level security filters the rest."""
    with session(user.person_id, user.role) as cur:
        logged = scalar(cur, "SELECT open_complaint(%s::int)", (cid,))
        overview = fetch_one(cur, "SELECT * FROM v_complaint_overview WHERE complaint_id = %s", (cid,))
        if overview is None:
            raise HTTPException(404, "Complaint not found")
        page = {
            "complaint": overview,
            "access_logged": logged,
            "me": {
                "is_complainant": scalar(cur, "SELECT is_complainant(%s::int)", (cid,)),
                "is_handler": scalar(cur, "SELECT is_current_handler(%s::int)", (cid,)),
                "is_committee": scalar(cur, "SELECT is_committee_handler(%s::int)", (cid,)),
            },
            "details": try_fetch(cur, "SELECT field_name, value, source FROM complaint_detail"
                                      " WHERE complaint_id = %s ORDER BY field_name", (cid,)),
            "identity": try_fetch(cur, "SELECT person_name(person_id) AS name, contact_consent"
                                       " FROM complainant_identity WHERE complaint_id = %s",
                                  (cid,), one=True),
            "parties": try_fetch(cur, "SELECT party_no, party_role, stated_role, description,"
                                      " person_name(person_id) AS name FROM complaint_party"
                                      " WHERE complaint_id = %s ORDER BY party_no", (cid,)),
            "clarifications": try_fetch(cur, "SELECT * FROM clarification WHERE complaint_id = %s"
                                             " ORDER BY seq_no", (cid,)),
            "routing": try_fetch(cur, """
                SELECT d.decision_id, d.decision_type, d.reason, d.decided_at, d.due_at,
                       person_name(d.assigned_person_id) AS assigned_person, cm.name AS committee
                FROM routing_decision d LEFT JOIN committee cm ON cm.committee_id = d.assigned_committee_id
                WHERE d.complaint_id = %s ORDER BY d.decision_id""", (cid,)),
            "exclusions": try_fetch(cur, """
                SELECT e.decision_id, person_name(e.person_id) AS person, e.reason_code,
                       conflict_label(e.reason_code) AS reason
                FROM conflict_exclusion e JOIN routing_decision d USING (decision_id)
                WHERE d.complaint_id = %s ORDER BY e.decision_id""", (cid,)),
            "timeline": try_fetch(cur, "SELECT at, kind, title, detail FROM v_complaint_timeline"
                                       " WHERE complaint_id = %s ORDER BY at, kind = 'Routing', kind", (cid,)),
            "ai": try_fetch(cur, """
                SELECT a.urgency, a.confidence, a.sensitivity_flag, a.summary,
                       c.name AS suggested_category, a.reviewed_at,
                       person_name(a.reviewed_by) AS reviewed_by
                FROM ai_triage_result a LEFT JOIN category c ON c.category_id = a.suggested_category_id
                WHERE a.complaint_id = %s""", (cid,), one=True),
            "disputes": try_fetch(cur, "SELECT * FROM question_dispute WHERE complaint_id = %s"
                                       " ORDER BY question_no", (cid,)),
            "marks_changes": try_fetch(cur, "SELECT question_no, old_marks, new_marks, changed_at,"
                                            " person_name(changed_by) AS changed_by, reason"
                                            " FROM marks_change_log WHERE complaint_id = %s"
                                            " ORDER BY change_id", (cid,)),
            "appeals": try_fetch(cur, "SELECT appeal_id, filed_on, grounds, status, outcome,"
                                      " person_name(heard_by) AS heard_by FROM appeal"
                                      " WHERE complaint_id = %s ORDER BY appeal_id", (cid,)),
        }
        page["reopened_as"] = scalar(cur, "SELECT complaint_id FROM complaint WHERE reopened_from = %s",
                                     (cid,))
    return page


@router.post("/complaints/{cid}/answers")
def answer(cid: int, body: AnswerIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        status = scalar(cur, "SELECT answer_clarification(%s::int, %s::int, %s::text)", (cid, body.seq_no, body.answer))
    return {"result": status}


@router.post("/complaints/{cid}/rate")
def rate(cid: int, body: RateIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        cur.execute("SELECT rate_and_close(%s::int, %s::int)", (cid, body.rating))
    return {"result": "Closed"}


@router.post("/complaints/{cid}/reopen")
def reopen(cid: int, body: TextIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        new_id = scalar(cur, "SELECT reopen_complaint(%s::int, %s::text)", (cid, body.text))
    return {"complaint_id": new_id}


@router.post("/complaints/{cid}/appeal")
def appeal(cid: int, body: TextIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        appeal_id = scalar(cur, "SELECT file_appeal(%s::int, %s::text)", (cid, body.text))
    return {"appeal_id": appeal_id}


# ------------------------------------------------------------ handler actions
@router.patch("/complaints/{cid}/status")
def update_status(cid: int, body: StatusIn, user: User = Depends(current_user)):
    """A plain UPDATE: the column-level GRANT allows only these three columns,
    the trigger checks the move is allowed, RLS limits it to the handler's rows."""
    with session(user.person_id, user.role) as cur:
        cur.execute("SELECT set_config('app.status_note', %s, true)", (body.note or "",))
        cur.execute("""UPDATE complaint
                          SET status = %s,
                              resolution_outcome = coalesce(%s, resolution_outcome),
                              resolution_note = coalesce(%s, resolution_note)
                        WHERE complaint_id = %s""",
                    (body.status, body.resolution_outcome, body.resolution_note, cid))
        if cur.rowcount == 0:
            raise HTTPException(403, "You are not the current handler of this complaint")
    return {"result": body.status}


@router.post("/complaints/{cid}/request-info")
def request_info(cid: int, body: TextIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        seq = scalar(cur, "SELECT request_info(%s::int, %s::text)", (cid, body.text))
    return {"seq_no": seq, "result": "NeedsInfo"}
