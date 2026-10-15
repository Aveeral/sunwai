"""LLM triage: turns free text into structured JSON.

    "The LLM suggests, the database decides."

The model only fills in the category, urgency, sensitivity, a summary,
the details it can find, and the people mentioned. Routing, priority,
completeness and access are all done by the database afterwards.

Safety nets:
  * the text is redacted first (no names / phone numbers leave the server)
  * the answer is validated; anything invalid is corrected or dropped
  * if the API fails (no key, no credit, timeout) we use the offline classifier
  * answers are cached on disk, so a demo gives the same result every time
"""
import hashlib
import json
import logging

from pydantic import BaseModel, Field, ValidationError, field_validator

from ..config import settings
from . import fallback

log = logging.getLogger("sunwai.llm")

PROMPT_VERSION = "v2"


class Person(BaseModel):
    ref: str | None = None                       # "[PERSON_1]" or null if unnamed
    party_role: str = "Respondent"
    stated_role: str = "Unknown"
    description: str | None = None

    @field_validator("party_role")
    @classmethod
    def _pr(cls, v):
        return v if v in ("Respondent", "Witness") else "Respondent"

    @field_validator("stated_role")
    @classmethod
    def _sr(cls, v):
        return v if v in ("Student", "Faculty", "Staff", "Unknown") else "Unknown"


class Triage(BaseModel):
    category_id: int
    confidence: float = Field(ge=0, le=1)
    urgency: str
    sensitive: bool = False
    summary: str = ""
    details: dict[str, str] = {}
    people: list[Person] = []
    reasoning: str = ""

    @field_validator("urgency")
    @classmethod
    def _u(cls, v):
        v = str(v).title()
        return v if v in ("Low", "Medium", "High") else "Medium"

    @field_validator("details", mode="before")
    @classmethod
    def _d(cls, v):
        if not isinstance(v, dict):
            return {}
        return {str(k): str(x) for k, x in v.items() if x not in (None, "", "null", "unknown")}


def build_prompt(categories: list[dict], requirements: list[dict]) -> str:
    fields: dict[int, list[str]] = {}
    for r in requirements:
        fields.setdefault(r["category_id"], []).append(
            r["field_name"] + ("*" if r["is_mandatory"] else ""))
    lines = [f'{c["category_id"]}: {c["name"]} [{c["domain"]}'
             f'{", SENSITIVE" if c["sensitivity"] == "Sensitive" else ""}]'
             f' fields: {", ".join(fields.get(c["category_id"], [])) or "-"}'
             for c in categories]
    return f"""You are the triage assistant of the grievance cell of Netaji Subhas University
of Technology (NSUT), Delhi. Students write complaints in English, Hindi or Hinglish.
Read ONE complaint and reply with ONE JSON object, nothing else.

CATEGORIES (id: name [domain] fields; * = mandatory):
{chr(10).join(lines)}

RULES
- category_id: the single best category. Use 15 only if nothing fits.
- confidence: 0..1, how sure you are of the category. Below 0.7 a human checks it.
- urgency: "High" for any risk to safety or health (fire, sparks, injury, threat), and
  for harassment, ragging, discrimination or faculty misconduct. "Medium" for things
  that block daily life (no water, no electricity, food hygiene, marks, exams).
  "Low" for inconvenience (slow Wi-Fi, broken chair, cleaning) unless it is
  blocking an exam or deadline that is very close.
- sensitive: true for harassment, ragging, discrimination and faculty conduct.
- summary: one neutral sentence in English, max 25 words, no opinions.
- details: ONLY the fields listed for the chosen category, ONLY if the text states
  them. Never guess. Normalise: hostel "BH-3" / "GH-1"; room_or_floor "Room 214"
  or "2nd floor"; exam "MidSem" / "EndSem"; question_numbers "3, 5".
- people: every [PERSON_n] in the text. Names were replaced by placeholders for
  privacy; keep the placeholder in "ref". stated_role from cues: sir / ma'am /
  prof / Dr / teacher => "Faculty"; senior / batchmate / roommate => "Student";
  caretaker / guard / warden / staff => "Staff"; otherwise "Unknown".
  party_role "Respondent" (the complaint is against them) or "Witness".
  If the complaint is against people who are not named (e.g. "some seniors"),
  add one entry with ref null and a short "description".
  NEVER list the person writing the complaint ("I", "me") as a party.
- reasoning: one short sentence on why you chose the category.

JSON SHAPE
{{"category_id": 1, "confidence": 0.9, "urgency": "Medium", "sensitive": false,
  "summary": "...", "details": {{"hostel": "BH-3"}},
  "people": [{{"ref": "[PERSON_1]", "party_role": "Respondent", "stated_role": "Faculty",
              "description": null}}],
  "reasoning": "..."}}"""


def _cache_path(key: str):
    settings.llm_cache_dir.mkdir(parents=True, exist_ok=True)
    return settings.llm_cache_dir / f"{key}.json"


def _call_openai(system: str, text: str) -> dict:
    from openai import OpenAI
    client = OpenAI(api_key=settings.openai_api_key, timeout=20, max_retries=1)
    resp = client.chat.completions.create(
        model=settings.openai_model,
        temperature=0,
        response_format={"type": "json_object"},
        messages=[{"role": "system", "content": system},
                  {"role": "user", "content": f"COMPLAINT:\n{text}"}],
    )
    return json.loads(resp.choices[0].message.content)


def analyze(redacted: str, categories: list[dict], requirements: list[dict],
            course_names: list[str]) -> tuple[dict, str]:
    """Returns (validated triage dict, engine name)."""
    valid_ids = {c["category_id"] for c in categories}

    if settings.use_openai:
        system = build_prompt(categories, requirements)
        key = hashlib.sha256(f"{PROMPT_VERSION}|{settings.openai_model}|{system}|{redacted}"
                             .encode()).hexdigest()[:24]
        path = _cache_path(key)
        try:
            if path.exists():
                raw, engine = json.loads(path.read_text()), f"{settings.openai_model} (cached)"
            else:
                raw, engine = _call_openai(system, redacted), settings.openai_model
            result = Triage.model_validate(raw)
            if result.category_id not in valid_ids:
                result.category_id, result.confidence = 15, 0.0
            if not path.exists():
                path.write_text(json.dumps(raw, indent=2))
            return result.model_dump(), engine
        except (ValidationError, ValueError, KeyError) as e:
            log.warning("LLM answer was invalid (%s); using offline classifier", e)
            engine = "offline (LLM answer invalid)"
        except Exception as e:   # network, quota, auth ...
            log.warning("LLM call failed (%s); using offline classifier", e)
            engine = "offline (LLM unavailable)"
    else:
        engine = "offline"

    return Triage.model_validate(fallback.analyze(redacted, course_names)).model_dump(), engine
