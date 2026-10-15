"""Database access.

Every request runs inside ONE transaction that first does:

    SET LOCAL search_path TO sunwai, public
    set_config('app.user_id', <person>)    -> read by current_person_id()
    set_config('app.role',    <role>)      -> written to access_log
    set_config('app.now',     <demo time>) -> read by app_now() (demo clock)
    SET LOCAL ROLE <role>                  -> e.g. sunwai_student

So every permission check (GRANTs, column privileges, row-level security)
is done by PostgreSQL itself. The Python code never decides who may see what.
"""
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone

from psycopg import errors, sql
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import settings

# The only roles the backend may switch to (whitelist: the role name is
# put into SQL as an identifier, so it must never come from the user directly).
ROLES = {
    "sunwai_student", "sunwai_handler", "sunwai_triage", "sunwai_icc",
    "sunwai_antiragging", "sunwai_sgrc", "sunwai_ombudsperson", "sunwai_admin",
}

pool = ConnectionPool(settings.database_url, min_size=1, max_size=10, open=False,
                      kwargs={"autocommit": True, "row_factory": dict_row})


# ---------------------------------------------------------------- demo clock
# The demo can move time forward (e.g. +72 hours) to show escalation live.
# Only app_now() inside the database sees this; nothing is really changed.
_clock = {"offset_hours": 0.0}


def clock_offset() -> float:
    return _clock["offset_hours"]


def set_clock_offset(hours: float) -> None:
    _clock["offset_hours"] = max(0.0, float(hours))


def demo_now() -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=_clock["offset_hours"])


# ---------------------------------------------------------------- sessions
@contextmanager
def session(person_id: int | None, role: str):
    """A transaction acting as `person_id` with database role `role`."""
    if role not in ROLES:
        raise ValueError(f"unknown role {role}")
    now = demo_now().isoformat() if _clock["offset_hours"] else ""
    with pool.connection() as conn, conn.transaction():
        cur = conn.cursor()
        cur.execute("SET LOCAL search_path TO sunwai, public")
        cur.execute("SELECT set_config('app.user_id', %s, true),"
                    "       set_config('app.role', %s, true),"
                    "       set_config('app.now', %s, true)",
                    ("" if person_id is None else str(person_id), role, now))
        cur.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(role)))
        yield cur


def system_session():
    """Background jobs and reference lookups run as the administrator role
    (no person). Admin still cannot read sensitive complaints."""
    return session(None, "sunwai_admin")


@contextmanager
def savepoint(cur):
    """Run part of a request so that a failure (e.g. permission denied)
    does not abort the whole transaction."""
    with cur.connection.transaction():
        yield


def try_fetch(cur, query, params=None, one=False):
    """Fetch rows; returns the string 'hidden' if this role may not read them.
    Used on the complaint page to show which parts DCL hides from a role."""
    try:
        with savepoint(cur):
            cur.execute(query, params)
            return cur.fetchone() if one else cur.fetchall()
    except errors.InsufficientPrivilege:
        return "hidden"


def fetch_all(cur, query, params=None):
    cur.execute(query, params)
    return cur.fetchall()


def fetch_one(cur, query, params=None):
    cur.execute(query, params)
    return cur.fetchone()


def scalar(cur, query, params=None):
    cur.execute(query, params)
    row = cur.fetchone()
    return None if row is None else next(iter(row.values()))
