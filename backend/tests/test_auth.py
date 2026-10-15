"""Demo login and tokens."""


def test_demo_users_lists_every_group(client):
    groups = client.get("/api/demo-users").json()
    assert [g["title"] for g in groups] == ["Students", "Offices", "Committees", "Oversight"]
    names = {p["name"] for g in groups for p in g["people"]}
    assert "Aarav Mehta" in names and "Mohan Lal" in names


def test_roles_come_from_the_database(client):
    r = client.post("/api/login", json={"person_id": 141}).json()   # ICC chair
    assert r["user"]["role"] == "sunwai_icc"
    assert "sunwai_handler" in r["user"]["roles"]


def test_cannot_take_a_role_you_do_not_hold(client):
    r = client.post("/api/login", json={"person_id": 1001, "role": "sunwai_admin"})
    assert r.status_code == 403


def test_requests_need_a_valid_token(client, login):
    assert client.get("/api/complaints/mine").status_code == 401
    token = login(1001)["Authorization"]
    forged = token.replace("sunwai_student", "sunwai_admin")
    assert client.get("/api/complaints/mine", headers={"Authorization": forged}).status_code == 401


def test_me_returns_profile(client, login):
    me = client.get("/api/me", headers=login(1001)).json()
    assert me["profile"]["hostel"] == "BH-3"
    assert me["profile"]["room_no"] == "214"
