"""DCL through the API: every refusal here comes from PostgreSQL, not Python."""
import pytest


def _attempt(client, h, action):
    return client.post("/api/demo/try-access", headers=h, json={"action": action}).json()


def test_student_cannot_open_handler_queue(client, login):
    r = client.get("/api/handler/queue", headers=login(1001))
    assert r.status_code == 403
    assert r.json()["detail"] == "permission denied for view v_handler_queue"


def test_committees_cannot_read_each_others_cases(client, login):
    assert client.get("/api/committee/cases/icc", headers=login(1001)).status_code == 403
    assert client.get("/api/committee/cases/sgrc", headers=login(141)).status_code == 403
    assert client.get("/api/committee/cases", headers=login(141)).status_code == 200


def test_student_cannot_open_someone_elses_complaint(client, login, file):
    _, f = file(1001, "The tap in the washroom is leaking badly")
    r = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(1002))
    assert r.status_code == 403


def test_rls_limits_rows_even_for_select_star(client, login):
    mine = len(client.get("/api/complaints/mine", headers=login(1001)).json())
    r = _attempt(client, login(1001), "read_all_complaints")
    assert r["allowed"] and r["rows"][0]["rows_visible"] == mine


@pytest.mark.parametrize("person,role,action", [
    (1001, None, "read_phone_numbers"),           # column privilege
    (203, None, "edit_description"),              # handler may only update status columns
    (203, None, "change_priority"),
    (203, None, "delete_history"),                # append-only
    (209, None, "read_identity"),                 # admin never sees who complained
    (1001, None, "read_access_log"),
    (209, None, "delete_access_log"),         # even the admin cannot erase the audit log
])
def test_forbidden_actions_are_refused(client, login, person, role, action):
    r = _attempt(client, login(person, role), action)
    assert r["allowed"] is False, r
    assert "permission denied" in r["error"] or "append-only" in r["error"].lower()


def test_admin_sees_analytics_but_not_sensitive_cases(client, login, file):
    _, f = file(1002, "A senior keeps stalking me and sending vulgar messages",
                people=[{"person_id": None, "party_role": "Respondent", "stated_role": "Student",
                         "description": "A senior"}])
    admin = login(209)
    assert client.get("/api/analytics", headers=admin).status_code == 200
    assert client.get(f"/api/complaints/{f['complaint_id']}", headers=admin).status_code == 403
    ids = [c["complaint_id"] for c in client.get("/api/admin/complaints", headers=admin).json()]
    assert f["complaint_id"] not in ids


def test_opening_a_confidential_case_is_logged(client, login, file):
    _, f = file(1002, "Ram sir keeps sending me inappropriate messages",
                people=[{"person_id": 101, "party_role": "Respondent", "stated_role": "Faculty"}])
    page = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(141)).json()  # ICC chair
    assert page["access_logged"] is True
    log = client.get("/api/admin/access-log", headers=login(209)).json()
    assert any(e["complaint_id"] == f["complaint_id"] and e["db_role"] == "sunwai_icc" for e in log)


def test_admin_page_hides_sections_without_grant(client, login, file):
    _, f = file(1001, "Fan is not working in my room")
    page = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(209)).json()
    assert page["identity"] == "hidden" and page["parties"] == "hidden"
