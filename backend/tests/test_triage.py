"""Redaction, the offline classifier, and filing through the API."""
from app.services import fallback
from app.services.redaction import redact, unredact


# ---------------------------------------------------------------- redaction
def test_names_and_contacts_never_reach_the_llm():
    text, mapping = redact("Ram Kumar sir called me on 9876543210, mail ram@nsut.ac.in, roll 2025UCD2177")
    assert "Ram" not in text and "9876543210" not in text and "nsut.ac.in" not in text
    assert "[PERSON_1]" in text and "[PHONE]" in text and "[EMAIL]" in text and "[ROLL_NO]" in text
    assert mapping["[PERSON_1]"] == "Ram Kumar"
    assert unredact("[PERSON_1] was rude", mapping) == "Ram Kumar was rude"


def test_same_name_twice_gets_one_placeholder():
    text, mapping = redact("Neha said Neha would fix it")
    assert text.count("[PERSON_1]") == 2 and len(mapping) == 1


# ---------------------------------------------------------------- classifier
def test_hinglish_water_complaint():
    r = fallback.analyze("BH-3 washroom mein paani nahi aa raha, 2nd floor")
    assert r["category_id"] == 1 and r["urgency"] == "Medium"
    assert r["details"]["hostel"] == "BH-3" and r["details"]["room_or_floor"] == "2nd floor"


def test_harassment_is_sensitive_and_high():
    r = fallback.analyze("[PERSON_1] sir keeps sending me inappropriate messages at night")
    assert r["category_id"] == 12 and r["sensitive"] and r["urgency"] == "High"
    assert r["people"][0]["stated_role"] == "Faculty"


def test_wifi_is_low_but_sparks_are_high():
    assert fallback.analyze("wifi is very slow in my room")["urgency"] == "Low"
    assert fallback.analyze("sparks coming from the switch board in my room")["urgency"] == "High"


def test_nothing_matches_goes_to_general():
    r = fallback.analyze("I want to talk to someone about something")
    assert r["category_id"] == 15 and r["confidence"] < 0.7


# ---------------------------------------------------------------- preview
def test_preview_shows_checklist_and_candidates(client, login):
    p = client.post("/api/triage/preview", headers=login(1001), json={
        "description": "Ram sir from DBMS keeps sending me inappropriate messages at night"}).json()
    assert p["category"]["name"] == "Sexual harassment"
    assert p["priority"] == "High" and p["sensitive"]
    assert "Ram" not in p["redacted_text"]
    cands = p["people"][0]["candidates"]
    assert cands[0]["full_name"] == "Dr. Ram Kumar"                # teaches his course: ranked first
    assert "Teaches your course" in cands[0]["connection"]
    assert all("Vikram" not in c["full_name"] for c in cands)     # "Ram" must start a word
    assert p["route_hint"] == "the Internal Complaints Committee"


def test_preview_fills_hostel_from_profile(client, login):
    p = client.post("/api/triage/preview", headers=login(1001),
                    json={"description": "no water in the washroom since morning"}).json()
    items = {i["field"]: i for i in p["checklist"]}
    assert items["hostel"]["value"] == "BH-3" and items["hostel"]["source"] == "Profile"
    assert items["room_or_floor"]["value"] == "Room 214"


# ---------------------------------------------------------------- filing
def test_water_complaint_goes_to_the_caretaker(client, login, file):
    _, f = file(1001, "Hostel washroom mein paani nahi aa raha since yesterday")
    assert f["result"] == "Assigned"
    page = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(1001)).json()
    assert page["complaint"]["assigned_person"] == "Dinesh Kumar"       # Caretaker BH-3
    assert page["complaint"]["priority"] == "Medium"
    sources = {d["field_name"]: d["source"] for d in page["details"]}
    assert sources["hostel"] == "Profile"


def test_missing_detail_asks_a_question_then_routes(client, login, file):
    _, f = file(1004, "The projector is not working, classes are getting affected")
    assert f["result"] == "NeedsInfo"
    cid = f["complaint_id"]
    h = login(1004)
    q = client.get(f"/api/complaints/{cid}", headers=h).json()["clarifications"]
    assert q[0]["field_name"] == "building_room" and q[0]["answer"] is None
    r = client.post(f"/api/complaints/{cid}/answers", headers=h,
                    json={"seq_no": q[0]["seq_no"], "answer": "CSE block, room 204"})
    assert r.json()["result"] == "Assigned"


def test_details_typed_on_the_form_skip_the_question(client, file):
    _, f = file(1004, "The projector is not working", details={"building_room": "ECE block room 12"})
    assert f["result"] == "Assigned"


def test_harassment_goes_to_icc_with_recusal(client, login, file):
    _, f = file(1002, "Ram sir keeps sending me inappropriate messages at night",
                people=[{"person_id": 101, "party_role": "Respondent", "stated_role": "Faculty"}])
    assert f["result"] == "Assigned"
    page = client.get(f"/api/complaints/{f['complaint_id']}", headers=login(1002)).json()
    assert page["complaint"]["visibility"] == "Confidential"
    assert page["complaint"]["assigned_committee"] == "Internal Complaints Committee"
    recused = {e["person"]: e["reason_code"] for e in page["exclusions"]}
    assert recused.get("Dr. Vikram Sethi") == "SameDepartment"


def test_anonymous_ragging_hides_identity(client, login, file):
    _, f = file(1005, "Seniors forced us freshers to do intro at night in the hostel",
                visibility="Anonymous")
    cid = f["complaint_id"]
    page = client.get(f"/api/complaints/{cid}", headers=login(171)).json()   # Anti-Ragging chair
    assert page["complaint"]["assigned_committee"] == "Anti-Ragging Committee"
    assert page["identity"] in (None, "hidden")


def test_unclear_complaint_waits_for_the_triage_officer(client, login, file):
    _, f = file(1006, "I want to talk to someone about something that happened")
    cid = f["complaint_id"]
    assert f["result"] == "AwaitingTriage"
    queue = client.get("/api/triage/queue", headers=login(210)).json()
    assert cid in [c["complaint_id"] for c in queue]
    r = client.post(f"/api/triage/{cid}/confirm", headers=login(210), json={"category_id": 10})
    assert r.status_code == 200 and r.json()["result"] in ("NeedsInfo", "Assigned")


def test_model_output_is_cleaned(client, login, monkeypatch):
    """Placeholders in details are turned back into names, and an unnamed
    'party' next to a named one (usually the complainant) is dropped."""
    from app.services import llm as llm_mod
    monkeypatch.setattr(llm_mod.settings, "llm_mode", "openai")
    monkeypatch.setattr(llm_mod, "_call_openai", lambda s, t: {
        "category_id": 12, "confidence": 0.95, "urgency": "High", "sensitive": True,
        "summary": "x", "details": {"respondent_identity": "[PERSON_1]"},
        "people": [{"ref": "[PERSON_1]", "party_role": "Respondent", "stated_role": "Faculty"},
                   {"ref": None, "party_role": "Respondent", "description": "The student"}]})
    p = client.post("/api/triage/preview", headers=login(1001),
                    json={"description": "Ram sir keeps sending me messages at night"}).json()
    items = {i["field"]: i["value"] for i in p["checklist"]}
    assert items["respondent_identity"] == "Ram"
    assert len(p["people"]) == 1
