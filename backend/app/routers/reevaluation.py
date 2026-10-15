"""Exam module: answer scripts, re-evaluation requests, reviewer decisions."""
from fastapi import APIRouter, Depends

from ..auth import User, current_user
from ..db import fetch_all, scalar, session
from ..schemas import DecideDisputeIn, ReevaluationIn

router = APIRouter(prefix="/api", tags=["re-evaluation"])


@router.get("/scripts/mine")
def my_scripts(user: User = Depends(current_user)):
    """My evaluated answer scripts (RLS: only my own rows)."""
    with session(user.person_id, user.role) as cur:
        return fetch_all(cur, """
            SELECT s.script_id, s.total_marks, s.shown_on, e.exam_type, e.exam_date, e.max_marks,
                   co.course_code, co.title,
                   (SELECT c.complaint_id FROM complaint c WHERE c.script_id = s.script_id
                    ORDER BY c.complaint_id DESC LIMIT 1) AS reevaluation_id
            FROM answer_script s
            JOIN exam e USING (exam_id)
            JOIN course_offering o ON o.offering_id = e.offering_id
            JOIN course co ON co.course_code = o.course_code
            WHERE s.student_id = current_person_id()
            ORDER BY e.exam_date DESC""")


@router.post("/reevaluations")
def file_reevaluation(body: ReevaluationIn, user: User = Depends(current_user)):
    from psycopg.types.json import Jsonb
    with session(user.person_id, user.role) as cur:
        cid = scalar(cur, "SELECT file_reevaluation(%s::int, %s::jsonb)",
                     (body.script_id, Jsonb([d.model_dump() for d in body.disputes])))
    return {"complaint_id": cid}


@router.post("/reevaluations/{cid}/decide")
def decide(cid: int, body: DecideDisputeIn, user: User = Depends(current_user)):
    with session(user.person_id, user.role) as cur:
        result = scalar(cur, "SELECT decide_dispute(%s::int, %s::int, %s::text, %s::numeric)",
                        (cid, body.question_no, body.decision, body.revised_marks))
    return {"result": result}
