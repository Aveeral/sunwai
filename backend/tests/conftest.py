"""Test setup. Runs the API in-process against the database in DATABASE_URL,
with the OFFLINE classifier (no OpenAI calls, no cost, same answer every time).

Reset the database first:   bash scripts/reset_db.sh
"""
import os

os.environ["LLM_MODE"] = "offline"
os.environ["SCHEDULER_SECONDS"] = "0"

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def login(client):
    cache = {}

    def _login(person_id: int, role: str | None = None) -> dict:
        key = (person_id, role)
        if key not in cache:
            r = client.post("/api/login", json={"person_id": person_id, "role": role})
            assert r.status_code == 200, r.text
            cache[key] = {"Authorization": "Bearer " + r.json()["token"]}
        return cache[key]
    return _login


@pytest.fixture(scope="session")
def file(client, login):
    """Preview + file in one go. Returns (preview, filed)."""
    def _file(person_id, text, details=None, people=None, visibility="Public", role=None):
        h = login(person_id, role)
        p = client.post("/api/triage/preview", json={"description": text}, headers=h)
        assert p.status_code == 200, p.text
        body = {"analysis_id": p.json()["analysis_id"], "visibility": visibility,
                "details": details or {}}
        if people is not None:
            body["people"] = people
        f = client.post("/api/complaints", json=body, headers=h)
        assert f.status_code == 200, f.text
        return p.json(), f.json()
    return _file
