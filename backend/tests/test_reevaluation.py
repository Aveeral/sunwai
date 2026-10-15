"""Exam module through the API."""


def test_reevaluation_goes_to_an_independent_reviewer(client, login):
    aarav = login(1001)
    scripts = client.get("/api/scripts/mine", headers=aarav).json()
    free = [s for s in scripts if s["reevaluation_id"] is None]
    assert free, "reset the database: every script already has a re-evaluation"
    s = free[0]
    r = client.post("/api/reevaluations", headers=aarav, json={"script_id": s["script_id"], "disputes": [
        {"question_no": 2, "marks_awarded": 3, "marks_claimed": 5, "reason": "Step marks not given"},
        {"question_no": 4, "marks_awarded": 6, "marks_claimed": 8, "reason": "Correct answer marked wrong"}]})
    assert r.status_code == 200, r.text
    cid = r.json()["complaint_id"]

    page = client.get(f"/api/complaints/{cid}", headers=aarav).json()
    reviewer = page["complaint"]["assigned_person_id"]
    assert any(e["reason_code"] == "OriginalEvaluator" for e in page["exclusions"])

    h = login(reviewer)
    assert client.post(f"/api/reevaluations/{cid}/decide", headers=h, json={
        "question_no": 2, "decision": "Accepted", "revised_marks": 5}).json()["result"] == "InProgress"
    assert client.post(f"/api/reevaluations/{cid}/decide", headers=h, json={
        "question_no": 4, "decision": "Rejected"}).json()["result"] == "Resolved"

    page = client.get(f"/api/complaints/{cid}", headers=aarav).json()
    assert page["complaint"]["resolution_outcome"] == "Upheld"
    assert [(m["question_no"], float(m["new_marks"])) for m in page["marks_changes"]] == [(2, 5.0)]


def test_cannot_request_reevaluation_of_someone_elses_script(client, login):
    s = client.get("/api/scripts/mine", headers=login(1001)).json()[0]
    r = client.post("/api/reevaluations", headers=login(1002), json={"script_id": s["script_id"],
                    "disputes": [{"question_no": 1, "marks_awarded": 1, "marks_claimed": 2,
                                  "reason": "please"}]})
    assert r.status_code in (400, 403)
