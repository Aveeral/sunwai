"""Demo login.

The project is about the database, so login is a simple "log in as" picker:
you choose a person (and one of the roles that person really holds), and
the backend gives a signed token "person.role.signature". Each request then
runs as that person with that database role (see db.session).

Which roles a person may use is decided from the database:
    everyone                         -> sunwai_student (anyone may file)
    faculty / staff                  -> sunwai_handler
    ICC / Anti-Ragging / SGRC member -> sunwai_icc / sunwai_antiragging / sunwai_sgrc
    Ombudsperson                     -> sunwai_ombudsperson
    holds the Triage Officer post    -> sunwai_triage
    holds the Registrar post         -> sunwai_admin
"""
import hashlib
import hmac
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException

from .config import settings
from .db import fetch_one, system_session

ROLE_ORDER = ["sunwai_admin", "sunwai_ombudsperson", "sunwai_triage", "sunwai_icc",
              "sunwai_antiragging", "sunwai_sgrc", "sunwai_handler", "sunwai_student"]

ROLE_LABELS = {
    "sunwai_student": "Complainant",
    "sunwai_handler": "Office handler",
    "sunwai_triage": "Triage officer",
    "sunwai_icc": "ICC member",
    "sunwai_antiragging": "Anti-Ragging Committee",
    "sunwai_sgrc": "SGRC member",
    "sunwai_ombudsperson": "Ombudsperson",
    "sunwai_admin": "Administrator",
}

PERSON_ROLES_SQL = """
SELECT p.person_id, person_name(p.person_id) AS name, p.person_type,
       d.name AS unit,
       (SELECT string_agg(title, ', ' ORDER BY position_id)
          FROM position WHERE holder_id = p.person_id) AS posts,
       array_remove(ARRAY[
         'sunwai_student',
         CASE WHEN p.person_type <> 'Student' THEN 'sunwai_handler' END,
         CASE WHEN EXISTS (SELECT 1 FROM committee_member m JOIN committee c USING (committee_id)
                           WHERE m.person_id = p.person_id AND c.committee_type = 'ICC')
              THEN 'sunwai_icc' END,
         CASE WHEN EXISTS (SELECT 1 FROM committee_member m JOIN committee c USING (committee_id)
                           WHERE m.person_id = p.person_id AND c.committee_type = 'AntiRagging')
              THEN 'sunwai_antiragging' END,
         CASE WHEN EXISTS (SELECT 1 FROM committee_member m JOIN committee c USING (committee_id)
                           WHERE m.person_id = p.person_id AND c.committee_type = 'SGRC')
              THEN 'sunwai_sgrc' END,
         CASE WHEN EXISTS (SELECT 1 FROM committee_member m JOIN committee c USING (committee_id)
                           WHERE m.person_id = p.person_id AND c.committee_type = 'Ombudsperson')
              THEN 'sunwai_ombudsperson' END,
         CASE WHEN EXISTS (SELECT 1 FROM position WHERE holder_id = p.person_id
                           AND role_code = 'TriageOfficer') THEN 'sunwai_triage' END,
         CASE WHEN EXISTS (SELECT 1 FROM position WHERE holder_id = p.person_id
                           AND role_code = 'Registrar') THEN 'sunwai_admin' END
       ], NULL) AS roles
FROM person p JOIN department d ON d.unit_id = p.unit_id
WHERE p.person_id = %s
"""


@dataclass
class User:
    person_id: int
    role: str
    name: str = ""


def person_with_roles(person_id: int) -> dict | None:
    with system_session() as cur:
        row = fetch_one(cur, PERSON_ROLES_SQL, (person_id,))
    if row:
        row["roles"] = sorted(row["roles"], key=ROLE_ORDER.index)
    return row


def default_role(person: dict) -> str:
    """Students log in as complainants by default (a student who also sits on
    a committee can pick that role explicitly); staff get their most specific role."""
    if person["person_type"] == "Student":
        return "sunwai_student"
    return sorted(person["roles"], key=ROLE_ORDER.index)[0]


def _sign(payload: str) -> str:
    return hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()[:32]


def make_token(person_id: int, role: str) -> str:
    payload = f"{person_id}.{role}"
    return f"{payload}.{_sign(payload)}"


def read_token(token: str) -> User:
    try:
        pid, role, sig = token.split(".")
    except ValueError:
        raise HTTPException(401, "Invalid token")
    if not hmac.compare_digest(sig, _sign(f"{pid}.{role}")):
        raise HTTPException(401, "Invalid token")
    return User(int(pid), role)


def current_user(authorization: str | None = Header(default=None)) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Log in first")
    return read_token(authorization.split(" ", 1)[1].strip())


def require_role(*roles: str):
    """Only lets the request through if the user is logged in with one of
    these roles. (This is only for friendlier errors; the database would
    refuse anyway.)"""
    def dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, f"This needs one of the roles: {', '.join(roles)}")
        return user
    return dep
