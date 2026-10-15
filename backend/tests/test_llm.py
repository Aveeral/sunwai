"""The OpenAI path, with the API call replaced by a fake (no network, no cost)."""
from app.config import settings
from app.services import llm
from app.services.triage import reference


def _run(monkeypatch, tmp_path, fake):
    monkeypatch.setattr(settings, "llm_mode", "openai")
    monkeypatch.setattr(settings, "llm_cache_dir", tmp_path)
    monkeypatch.setattr(llm, "_call_openai", fake)
    ref = reference()
    return llm.analyze("[PERSON_1] sir shouted at me in class", ref["categories"],
                       ref["requirements"], ref["courses"])


def test_valid_answer_is_used_and_cached(monkeypatch, tmp_path):
    calls = []

    def fake(system, text):
        calls.append(text)
        assert "[PERSON_1]" in text and "CATEGORIES" in system
        return {"category_id": 11, "confidence": 0.88, "urgency": "high", "sensitive": True,
                "summary": "Student reports [PERSON_1] shouted in class.",
                "details": {"respondent_role": "Faculty", "junk": None},
                "people": [{"ref": "[PERSON_1]", "party_role": "Respondent", "stated_role": "Professor"}]}

    result, engine = _run(monkeypatch, tmp_path, fake)
    assert engine == settings.openai_model
    assert result["urgency"] == "High"                         # normalised
    assert result["people"][0]["stated_role"] == "Unknown"     # invalid value corrected
    assert "junk" not in result["details"]
    _, engine2 = _run(monkeypatch, tmp_path, fake)
    assert engine2.endswith("(cached)") and len(calls) == 1


def test_unknown_category_becomes_general(monkeypatch, tmp_path):
    result, _ = _run(monkeypatch, tmp_path, lambda s, t: {
        "category_id": 99, "confidence": 0.9, "urgency": "Low"})
    assert result["category_id"] == 15 and result["confidence"] == 0


def test_api_failure_falls_back_to_offline(monkeypatch, tmp_path):
    def boom(system, text):
        raise ConnectionError("no network")
    result, engine = _run(monkeypatch, tmp_path, boom)
    assert engine == "offline (LLM unavailable)" and result["category_id"] == 11


def test_garbage_answer_falls_back_to_offline(monkeypatch, tmp_path):
    result, engine = _run(monkeypatch, tmp_path, lambda s, t: {"hello": "world"})
    assert engine == "offline (LLM answer invalid)"
