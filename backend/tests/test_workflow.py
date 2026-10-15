"""Handler actions, rating, reopening, appeals, information requests."""


def _queue_ids(client, h):
    return [c["complaint_id"] for c in client.get("/api/handler/queue", headers=h).json()]


def _resolve(client, h, cid, outcome="Fixed"):
    assert client.patch(f"/api/complaints/{cid}/status", headers=h,
                        json={"status": "InProgress"}).status_code == 200
    r = client.patch(f"/api/complaints/{cid}/status", headers=h,
                     json={"status": "Resolved", "resolution_outcome": outcome,
                           "resolution_note": "Plumber fixed the pipe"})
    assert r.status_code == 200, r.text


def test_handler_sees_it_and_state_machine_is_enforced(client, login, file):
    _, f = file(1001, "Geyser not working, no hot water in the bathroom")
    cid, caretaker = f["complaint_id"], login(203)
    assert cid in _queue_ids(client, caretaker)
    bad = client.patch(f"/api/complaints/{cid}/status", headers=caretaker,
                       json={"status": "Resolved", "resolution_outcome": "Fixed"})
    assert bad.status_code == 400 and "Assigned" in bad.json()["detail"]
    _resolve(client, caretaker, cid)
    assert client.post(f"/api/complaints/{cid}/rate", headers=login(1001),
                       json={"rating": 4}).status_code == 200
    page = client.get(f"/api/complaints/{cid}", headers=login(1001)).json()
    assert page["complaint"]["status"] == "Closed" and page["complaint"]["feedback_rating"] == 4


def test_other_handler_cannot_update(client, login, file):
    _, f = file(1001, "Tap leaking in the washroom")
    r = client.patch(f"/api/complaints/{f['complaint_id']}/status", headers=login(167),
                     json={"status": "InProgress"})
    assert r.status_code == 403


def test_reopen_creates_linked_complaint(client, login, file):
    _, f = file(1001, "Light in my room is not working")
    cid = f["complaint_id"]
    _resolve(client, login(203), cid)
    r = client.post(f"/api/complaints/{cid}/reopen", headers=login(1001),
                    json={"text": "It stopped working again"})
    assert r.status_code == 200
    new = r.json()["complaint_id"]
    page = client.get(f"/api/complaints/{new}", headers=login(1001)).json()
    assert page["complaint"]["reopened_from"] == cid and page["complaint"]["status"] == "Assigned"
    again = client.post(f"/api/complaints/{cid}/reopen", headers=login(1001), json={"text": "again"})
    assert again.status_code == 400


def test_request_info_round_trip(client, login, file):
    _, f = file(1001, "Water cooler on my floor is leaking")
    cid, caretaker, aarav = f["complaint_id"], login(203), login(1001)
    r = client.post(f"/api/complaints/{cid}/request-info", headers=caretaker,
                    json={"text": "Which side of the floor is the cooler on?"})
    assert r.status_code == 200
    q = client.get(f"/api/complaints/{cid}", headers=aarav).json()["clarifications"]
    open_q = [x for x in q if x["answer"] is None][0]
    assert open_q["asked_by"] == "Handler"
    r = client.post(f"/api/complaints/{cid}/answers", headers=aarav,
                    json={"seq_no": open_q["seq_no"], "answer": "Near room 230"})
    assert r.json()["result"] == "Assigned"


def test_appeal_to_ombudsperson(client, login, file):
    _, f = file(1001, "Tap leaking near the stairs")
    cid = f["complaint_id"]
    _resolve(client, login(203), cid, outcome="Dismissed")
    r = client.post(f"/api/complaints/{cid}/appeal", headers=login(1001),
                    json={"text": "It was never fixed, the tap still leaks"})
    assert r.status_code == 200
    appeal_id = r.json()["appeal_id"]
    omb = login(172)
    assert appeal_id in [a["appeal_id"] for a in client.get("/api/appeals", headers=omb).json()]
    assert client.post(f"/api/appeals/{appeal_id}/decide", headers=login(1001),
                       json={"status": "Upheld", "outcome": "self-approval"}).status_code == 403
    r = client.post(f"/api/appeals/{appeal_id}/decide", headers=omb,
                    json={"status": "Upheld", "outcome": "Send the plumber again"})
    assert r.status_code == 200
    page = client.get(f"/api/complaints/{cid}", headers=login(1001)).json()
    assert page["complaint"]["status"] == "InProgress"


def test_timeline_records_every_step(client, login, file):
    _, f = file(1001, "Washroom tap is broken")
    tl = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(1001)).json()["timeline"]
    titles = " ".join(t["title"] for t in tl)
    assert "Filed" in titles and "Assigned" in titles
