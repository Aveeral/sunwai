"""Filing a complaint in two steps.

1. preview(): the student types the complaint. We redact it, ask the LLM
   (or the offline classifier), and show back:
     - the category, urgency, the priority the database will give it
     - a live checklist: which required details were found, which come
       from the student's profile, and which are still missing
     - each person mentioned, with real candidates from the database
       ("Did you mean Dr. Ram Kumar, who teaches your DBMS course?")
   Nothing is stored in the database yet.

2. file(): the student confirms (fills missing details, picks the right
   person). We call file_complaint() and record_ai_triage() in ONE
   transaction, and the database does everything else (completeness check,
   priority, routing, conflict check).
"""
import secrets
import time
from functools import lru_cache

from fastapi import HTTPException
from psycopg.types.json import Jsonb

from ..auth import User
from ..db import fetch_all, fetch_one, scalar, session, system_session
from . import llm
from .redaction import redact, unredact

ANALYSIS_TTL = 3600
_analyses: dict[str, dict] = {}

ROLE_LABEL = {
    "Caretaker": "the caretaker of the hostel",
    "Warden": "the warden of the hostel",
    "EstateOfficer": "the Estate Office (block in-charge)",
    "LabInCharge": "the lab in-charge of the department",
    "TimetableCoordinator": "the department timetable coordinator",
    "HOD": "the Head of Department",
    "CoE": "the Controller of Examinations",
    "ComputerCentreStaff": "the Computer Centre helpdesk",
    "TriageOfficer": "the Grievance Triage Officer (for a human check)",
}


@lru_cache(maxsize=1)
def reference() -> dict:
    """Categories, requirements, courses and routing rules (rarely change)."""
    with system_session() as cur:
        return {
            "categories": fetch_all(cur, "SELECT category_id, name, domain, sensitivity, base_priority,"
                                         " sla_hours, anonymous_allowed FROM category ORDER BY 1"),
            "requirements": fetch_all(cur, "SELECT category_id, field_name, is_mandatory, question_prompt"
                                           " FROM category_requirement ORDER BY category_id,"
                                           " is_mandatory DESC, field_name"),
            "courses": [r["n"] for r in fetch_all(
                cur, "SELECT course_code || ' ' || title AS n FROM course ORDER BY 1")],
            "routes": {r["category_id"]: r for r in fetch_all(
                cur, "SELECT DISTINCT ON (r.category_id) r.category_id, r.target_role_code,"
                     "       c.name AS committee"
                     " FROM routing_rule r LEFT JOIN committee c ON c.committee_id = r.target_committee_id"
                     " ORDER BY r.category_id, r.priority")},
        }


def _route_hint(category_id: int) -> str:
    r = reference()["routes"].get(category_id)
    if not r:
        return "the Grievance Triage Officer"
    if r["committee"]:
        return f"the {r['committee']}"
    return ROLE_LABEL.get(r["target_role_code"], r["target_role_code"])


def _purge():
    cutoff = time.time() - ANALYSIS_TTL
    for k in [k for k, v in _analyses.items() if v["created"] < cutoff]:
        _analyses.pop(k, None)


def _norm(s: str | None) -> str:
    return "".join(ch for ch in (s or "").lower() if ch.isalnum())


def preview(user: User, text: str) -> dict:
    text = text.strip()
    if len(text) < 10:
        raise HTTPException(400, "Please describe the problem in a little more detail.")
    ref = reference()
    redacted, mapping = redact(text)
    result, engine = llm.analyze(redacted, ref["categories"], ref["requirements"], ref["courses"])

    cat_id = result["category_id"]
    category = next(c for c in ref["categories"] if c["category_id"] == cat_id)
    reqs = [r for r in ref["requirements"] if r["category_id"] == cat_id]
    allowed = {r["field_name"] for r in reqs}
    # keep only the details this category asks for (the model may over-extract)
    # (and put real names back: the model only ever saw [PERSON_n])
    details = {k: unredact(v, mapping) for k, v in result["details"].items() if k in allowed}
    # an unnamed party is only kept when nobody was named (e.g. "some seniors");
    # this also drops the model's occasional mistake of listing the complainant
    if any(p["ref"] for p in result["people"]):
        result["people"] = [p for p in result["people"] if p["ref"]]
    summary = unredact(result["summary"], mapping)
    auto_accepted = (result["confidence"] >= 0.70 or result["sensitive"]) and cat_id != 15

    with session(user.person_id, user.role) as cur:
        profile = fetch_one(cur, "SELECT * FROM my_profile()")
        priority = scalar(cur, "SELECT compute_priority(%s::text, %s::text)",
                          (category["base_priority"], result["urgency"]))
        people = []
        for p in result["people"]:
            name = mapping.get(p["ref"]) if p["ref"] else None
            candidates = []
            if name:
                candidates = fetch_all(cur, "SELECT * FROM find_person_candidates(%s::text, %s::text)",
                                       (name, p["stated_role"]))
                if not candidates and p["stated_role"] != "Unknown":
                    candidates = fetch_all(cur, "SELECT * FROM find_person_candidates(%s::text, 'Unknown')",
                                           (name,))
            people.append({**p, "name": name, "candidates": candidates})

    # ---- live checklist (mirrors check_completeness + fill_from_profile)
    checklist = []
    has_respondent = any(p["party_role"] == "Respondent" for p in people)
    for r in reqs:
        f = r["field_name"]
        item = {"field": f, "mandatory": r["is_mandatory"], "question": r["question_prompt"],
                "value": details.get(f), "source": "AI" if f in details else None}
        if item["value"] is None and profile and profile.get("hostel"):
            if f == "hostel":
                item.update(value=profile["hostel"], source="Profile")
            elif f == "room_or_floor" and profile.get("room_no") and \
                    _norm(details.get("hostel", profile["hostel"])).find(_norm(profile["hostel"])) >= 0:
                item.update(value=f"Room {profile['room_no']}", source="Profile")
        if f in ("respondent_role", "respondent_identity") and item["value"] is None and has_respondent:
            resp = next(p for p in people if p["party_role"] == "Respondent")
            item.update(value=resp["stated_role"] if f == "respondent_role" else
                        (resp["name"] or resp.get("description")), source="AI")
            if item["value"] is None:
                item["source"] = None
        item["status"] = "ok" if item["value"] else ("missing" if r["is_mandatory"] else "optional")
        checklist.append(item)

    _purge()
    analysis_id = secrets.token_urlsafe(9)
    _analyses[analysis_id] = {"person_id": user.person_id, "created": time.time(), "text": text,
                              "result": {**result, "details": details, "summary": summary},
                              "people": people, "engine": engine}

    return {
        "analysis_id": analysis_id,
        "engine": engine,
        "redacted_text": redacted,             # exactly what the LLM saw
        "category": category,
        "confidence": result["confidence"],
        "auto_accepted": auto_accepted,
        "urgency": result["urgency"],
        "priority": priority,
        "sensitive": result["sensitive"] or category["sensitivity"] == "Sensitive",
        "summary": summary,
        "reasoning": unredact(result["reasoning"], mapping),
        "checklist": checklist,
        "people": people,
        "route_hint": _route_hint(cat_id) if auto_accepted else
                      "the Grievance Triage Officer, who will confirm the category",
        "anonymous_allowed": category["anonymous_allowed"],
        "profile": profile,
    }


def file(user: User, analysis_id: str, visibility: str, contact_consent: bool,
         user_details: dict[str, str], people: list[dict] | None) -> dict:
    a = _analyses.get(analysis_id)
    if not a or a["person_id"] != user.person_id:
        raise HTTPException(400, "This preview has expired. Please check the complaint again.")
    r = a["result"]

    if people is None:          # student did not change anything: use the AI's list
        parties = [{"person_id": None, "party_role": p["party_role"], "stated_role": p["stated_role"],
                    "description": p["name"] or p.get("description"), "source": "AI"}
                   for p in a["people"]]
    else:
        parties = [{"person_id": p.get("person_id"), "party_role": p.get("party_role", "Respondent"),
                    "stated_role": p.get("stated_role", "Unknown"),
                    "description": p.get("description"), "source": "User"} for p in people]
    user_details = {k: v for k, v in (user_details or {}).items() if v and str(v).strip()}

    with session(user.person_id, user.role) as cur:
        cid = scalar(cur, "SELECT file_complaint(%s::text, %s::text, %s::boolean)", (a["text"], visibility, contact_consent))
        status = scalar(cur, "SELECT record_ai_triage(%s::int, %s::int, %s::text, %s::numeric, %s::boolean,"
                        " %s::text, %s::jsonb, %s::jsonb, %s::jsonb)",
                        (cid, r["category_id"], r["urgency"], r["confidence"], r["sensitive"],
                         r["summary"], Jsonb(r["details"]), Jsonb(parties), Jsonb(user_details)))
        row = fetch_one(cur, "SELECT * FROM v_my_complaints WHERE complaint_id = %s", (cid,))
    _analyses.pop(analysis_id, None)
    return {"complaint_id": cid, "result": status, "complaint": row, "engine": a["engine"]}
