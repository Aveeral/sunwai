"""Offline triage: a keyword classifier used when there is no OpenAI key,
when the API call fails, and in the automated tests.

It returns exactly the same JSON shape as the LLM, so the rest of the
system cannot tell the difference. It understands common Hinglish words
(paani, bijli, khana, ...). It is deliberately simple; the LLM is better
at messy text, which the demo can show side by side.
"""
import re

# category_id -> keywords (English + Hinglish). Matching is on whole words / stems.
KEYWORDS: dict[int, list[str]] = {
    1: ["water", "paani", "pani", "tap", "geyser", "leak", "leakage", "washroom", "bathroom",
        "shower", "cooler water", "nal"],
    2: ["electricity", "bijli", "light", "power", "fan", "switch", "socket", "wiring",
        "short circuit", "light nahi", "power cut"],
    3: ["cleaning", "clean", "dirty", "safai", "kooda", "garbage", "dustbin", "bed", "mattress",
        "furniture", "almirah", "cupboard", "chair", "table", "pest", "cockroach", "rats"],
    4: ["mess", "food", "khana", "khaana", "dal", "roti", "breakfast", "lunch", "dinner",
        "nashta", "hygiene", "insect in", "stale", "canteen"],
    5: ["ac", "air conditioner", "classroom", "lecture hall", "building", "lift", "elevator",
        "projector", "smart board", "bench", "ceiling", "roof", "seepage", "block"],
    6: ["lab", "oscilloscope", "equipment", "multimeter", "lab pc", "workstation",
        "microscope", "kit", "instrument"],
    7: ["timetable", "time table", "clash", "slot", "overlap", "schedule"],
    8: ["internal marks", "internals", "attendance", "sessional", "assignment marks",
        "marks not uploaded", "attendance shortage", "detained"],
    9: ["re-evaluation", "reevaluation", "re evaluation", "recheck", "re-check", "rechecking",
        "result", "answer sheet", "answer script", "copy check", "totalling", "marks wrong",
        "midsem marks", "endsem marks"],
    10: ["wifi", "wi-fi", "internet", "network", "lan", "ims", "portal", "erp", "login",
         "password reset", "email id", "net nahi", "net slow"],
    11: ["rude", "insult", "insulted", "humiliate", "humiliated", "biased", "partial",
         "threaten", "threatened", "misbehave", "misbehaved", "shouted", "abused", "badtameezi",
         "fail kar dunga", "unfair"],
    12: ["harass", "harassed", "harassing", "harassment", "inappropriate", "touched", "touch",
         "stalking", "stalk", "sexual", "lewd", "vulgar", "messages at night", "uncomfortable",
         "molest", "creepy"],
    13: ["ragging", "ragged", "seniors forced", "senior forced", "fresher", "freshers",
         "intro", "bullied by seniors", "forced to"],
    14: ["discrimination", "discriminated", "caste", "religion", "gender bias", "casteist",
         "because i am", "because of my", "region", "disability", "racist"],
}

HIGH_RISK = ["unsafe", "danger", "fire", "spark", "short circuit", "injured", "injury",
             "bleeding", "suicide", "threat", "attack", "emergency", "collapsed", "electric shock"]

FACULTY_CUES = ["sir", "ma'am", "maam", "madam", "prof", "professor", "dr", "teacher",
                "faculty", "hod", "instructor"]
STUDENT_CUES = ["senior", "seniors", "batchmate", "classmate", "roommate", "student", "junior"]
STAFF_CUES = ["caretaker", "warden", "guard", "staff", "clerk", "attendant", "mess worker"]


def _has(text: str, kw: str) -> bool:
    return re.search(r"(?<![a-z])" + re.escape(kw), text) is not None


def _score(text: str) -> dict[int, int]:
    scores = {}
    for cat, words in KEYWORDS.items():
        s = sum(2 if " " in w else 1 for w in words if _has(text, w))
        if s:
            scores[cat] = s
    return scores


def _extract_details(raw: str, text: str, course_names: list[str]) -> dict[str, str]:
    d: dict[str, str] = {}
    m = re.search(r"\b(bh|gh)\s*-?\s*(\d)\b", text)
    if m:
        d["hostel"] = f"{m.group(1).upper()}-{m.group(2)}"
    elif "west campus hostel" in text:
        d["hostel"] = "West Campus Hostel"
    elif m := re.search(r"\b(boys|girls) hostel\s*-?\s*(\d)", text):
        d["hostel"] = f"{'BH' if m.group(1) == 'boys' else 'GH'}-{m.group(2)}"

    if m := re.search(r"\broom\s*(?:no\.?|number)?\s*-?\s*(\d{1,4}[a-z]?)", text):
        d["room_or_floor"] = f"Room {m.group(1).upper()}"
        d["building_room"] = f"Room {m.group(1).upper()}"
    elif m := re.search(r"\b(\d)(?:st|nd|rd|th)\s+floor|\b(ground)\s+floor", text):
        d["room_or_floor"] = f"{m.group(1) or 'Ground'}{'' if m.group(2) else _suffix(m.group(1))} floor"

    if m := re.search(r"\b(block\s*-?\s*\w+|\w+\s+block)\b", text):
        d["building_room"] = (m.group(1).title() + ", " + d["building_room"]) if "building_room" in d \
            else m.group(1).title()

    for meal in ["breakfast", "lunch", "dinner", "snacks"]:
        if meal in text:
            d["meal"] = meal.title()
    if "nashta" in text and "meal" not in d:
        d["meal"] = "Breakfast"

    if m := re.search(r"\b([a-z ]{2,30}?\s*lab)\b", text):
        d["lab_name"] = m.group(1).strip().title()
    for eq in ["oscilloscope", "projector", "multimeter", "computer", "pc", "microscope",
               "ac", "smart board", "printer"]:
        if re.search(rf"\b{eq}s?\b", text):
            d.setdefault("equipment", eq.upper() if len(eq) <= 3 else eq.title())
            d.setdefault("item", d["equipment"])
    for svc, label in [("wifi", "Wi-Fi"), ("wi-fi", "Wi-Fi"), ("ims", "IMS portal"),
                       ("portal", "IMS portal"), ("lan", "LAN"), ("internet", "Internet"),
                       ("email", "College email")]:
        if re.search(rf"\b{re.escape(svc)}\b", text):
            d.setdefault("device_or_service", label)

    for name in course_names:            # e.g. "CS301 Database Management Systems"
        code, _, title = name.partition(" ")
        if code.lower() in text or (title and title.lower() in text):
            d["course"] = name
            break
    if "dbms" in text and "course" not in d:
        d["course"] = "DBMS"

    if re.search(r"\bmid\s*-?\s*sem", text):
        d["exam"] = "MidSem"
    elif re.search(r"\bend\s*-?\s*sem", text):
        d["exam"] = "EndSem"
    qs = re.findall(r"\bq(?:uestion)?\s*\.?\s*(\d{1,2})\b", text)
    if qs:
        d["question_numbers"] = ", ".join(dict.fromkeys(qs))

    days = r"(monday|tuesday|wednesday|thursday|friday|saturday|mon|tue|wed|thu|fri|sat)"
    if m := re.search(days + r"[^.]{0,30}?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?(?:\s*-\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)?)?)", text):
        d["clash_details"] = f"{m.group(1).title()} {m.group(2).strip()}"

    if m := re.search(r"\b(since\s+[\w ]{3,20}?|(?:\d+|two|three|four|five)\s+days?|kal se|parso se|"
                      r"last\s+(?:week|month|night)|yesterday)\b", text):
        d["since_when"] = m.group(1)
        d.setdefault("incident_date", m.group(1))
    return d


def _suffix(n: str) -> str:
    return {"1": "st", "2": "nd", "3": "rd"}.get(n, "th")


def _stated_role(text: str, placeholder: str) -> str:
    """Look at the words around [PERSON_n] for 'sir', 'senior', 'warden'..."""
    i = text.find(placeholder.lower())
    window = text[max(0, i - 25): i + len(placeholder) + 25] if i >= 0 else ""
    for cues, role in [(FACULTY_CUES, "Faculty"), (STAFF_CUES, "Staff"), (STUDENT_CUES, "Student")]:
        if any(re.search(rf"(?<![a-z]){re.escape(c)}(?![a-z])", window) for c in cues):
            return role
    return "Unknown"


def analyze(redacted: str, course_names: list[str] | None = None) -> dict:
    text = redacted.lower()
    scores = _score(text)

    # sensitive categories win when present
    for sensitive in (12, 13, 14, 11):
        if sensitive in scores:
            cat = sensitive
            break
    else:
        cat = max(scores, key=scores.get) if scores else 15

    total = sum(scores.values()) or 1
    top = scores.get(cat, 0)
    confidence = 0.40 if cat == 15 else round(min(0.92, 0.62 + 0.10 * top) * (top / total) ** 0.5, 2)

    sensitive = cat in (11, 12, 13, 14)
    if sensitive or any(_has(text, w) for w in HIGH_RISK):
        urgency = "High"
    elif cat in (10, 3, 5):
        urgency = "Low"
    else:
        urgency = "Medium"

    details = _extract_details(redacted, text, course_names or [])

    people = []
    for ph in dict.fromkeys(re.findall(r"\[PERSON_\d+\]", redacted)):
        people.append({"ref": ph,
                       "party_role": "Respondent" if sensitive or cat in (8,) else "Witness",
                       "stated_role": _stated_role(text, ph)})
    if cat == 13 and not people and re.search(r"senior", text):
        people.append({"ref": None, "party_role": "Respondent", "stated_role": "Student",
                       "description": "Seniors (names not given)"})

    first = redacted.strip().split(".")[0]
    summary = (first[:140] + "...") if len(first) > 140 else first
    return {
        "category_id": cat,
        "confidence": confidence,
        "urgency": urgency,
        "sensitive": sensitive,
        "summary": summary,
        "details": details,
        "people": people,
        "reasoning": f"Keyword match (offline classifier); scores {scores or 'none'}",
    }
