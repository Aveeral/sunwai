"""Demo clock + escalation. Runs last because it escalates the demo data."""


def test_moving_the_clock_escalates_overdue_complaints(client, login, file):
    _, f = file(1003, "wifi is not working in BH-2 since morning")
    cid = f["complaint_id"]
    h = login(1003)
    before = client.get(f"/api/complaints/{cid}", headers=h).json()["complaint"]["assigned_person"]

    client.post("/api/demo/clock", headers=h, json={"advance_hours": 100})
    try:
        r = client.post("/api/demo/escalate", headers=h).json()
        assert r["escalated"] >= 1
        page = client.get(f"/api/complaints/{cid}", headers=h).json()
        assert page["complaint"]["status"] == "Escalated"
        assert page["complaint"]["assigned_person"] != before
        assert page["routing"][-1]["decision_type"] == "Escalation"
    finally:
        client.post("/api/demo/clock", headers=h, json={"offset_hours": 0})
