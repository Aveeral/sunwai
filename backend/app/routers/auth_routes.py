"""Demo login: pick a person, get a token."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import (ROLE_LABELS, User, current_user, default_role, make_token,
                    person_with_roles)
from ..db import fetch_one, session
from ..schemas import LoginIn

router = APIRouter(prefix="/api", tags=["login"])

# The people used in the demo script, grouped for the login screen.
DEMO_PEOPLE = [
    ("Students", [
        (1001, "sunwai_student", "BH-3 room 214. Water, electricity and DBMS re-evaluation cases"),
        (1002, "sunwai_student", "GH-1. Filed the harassment complaint (ICC)"),
        (1003, "sunwai_student", "BH-2. Wi-Fi complaint that is overdue"),
        (1004, "sunwai_student", "GH-1. Projector complaint waiting for details"),
        (1005, "sunwai_student", "BH-1. Anonymous ragging complaint"),
        (1006, "sunwai_student", "Day scholar. Internal-marks complaint about the HOD"),
    ]),
    ("Offices", [
        (203, "sunwai_handler", "Caretaker BH-3: hostel water / electricity queue"),
        (167, "sunwai_handler", "Warden BH-3: next step up from the caretaker"),
        (207, "sunwai_handler", "Computer Centre helpdesk: Wi-Fi queue"),
        (102, "sunwai_handler", "HOD CSE, also the independent re-evaluation reviewer"),
        (161, "sunwai_handler", "Dean Academics: gets cases when the HOD is conflicted"),
        (163, "sunwai_handler", "Controller of Examinations"),
    ]),
    ("Committees", [
        (141, "sunwai_icc", "ICC chair: sexual-harassment cases"),
        (103, "sunwai_icc", "ICC member recused from the case about a CSE colleague"),
        (131, "sunwai_sgrc", "SGRC chair: faculty conduct, discrimination"),
        (104, "sunwai_sgrc", "SGRC member recused (reports to the HOD)"),
        (171, "sunwai_antiragging", "Anti-Ragging Committee chair"),
    ]),
    ("Oversight", [
        (210, "sunwai_triage", "Triage officer: confirms uncertain AI categories"),
        (172, "sunwai_ombudsperson", "Ombudsperson: decides appeals"),
        (209, "sunwai_admin", "Registrar: analytics, audit log; cannot read sensitive cases"),
    ]),
]


@router.get("/demo-users")
def demo_users():
    groups = []
    for title, people in DEMO_PEOPLE:
        items = []
        for pid, role, blurb in people:
            p = person_with_roles(pid)
            if p:
                items.append({"person_id": pid, "name": p["name"], "posts": p["posts"],
                              "unit": p["unit"], "role": role, "role_label": ROLE_LABELS[role],
                              "roles": p["roles"], "blurb": blurb})
        groups.append({"title": title, "people": items})
    return groups


@router.post("/login")
def login(body: LoginIn):
    p = person_with_roles(body.person_id)
    if not p:
        raise HTTPException(404, "No such person")
    role = body.role or default_role(p)
    if role not in p["roles"]:
        raise HTTPException(403, f"{p['name']} does not hold the role {role}")
    return {"token": make_token(body.person_id, role),
            "user": {**p, "role": role, "role_label": ROLE_LABELS[role]}}


@router.get("/me")
def me(user: User = Depends(current_user)):
    p = person_with_roles(user.person_id)
    with session(user.person_id, user.role) as cur:
        profile = fetch_one(cur, "SELECT * FROM my_profile()") if user.role != "sunwai_admin" else None
    return {**p, "role": user.role, "role_label": ROLE_LABELS[user.role],
            "role_labels": {r: ROLE_LABELS[r] for r in p["roles"]}, "profile": profile}
