"""Privacy: remove names and contact details BEFORE the text goes to the LLM.

    "Ram sir ne mujhe 9876543210 pe call kiya"
 -> "[PERSON_1] sir ne mujhe [PHONE] pe call kiya"     (mapping: PERSON_1 -> "Ram")

Names are recognised by matching words against the first and last names in
the person table, so the LLM never sees who a complaint is about. The
backend maps [PERSON_n] back to the name and asks the database for real
candidates (find_person_candidates).
"""
import re
from functools import lru_cache

from ..db import fetch_all, system_session


# words that are also names in our data but usually mean something else
NOT_NAMES = {"mess", "lab", "room", "hall", "block", "wing", "floor", "bh", "gh",
             "sir", "madam", "the", "and", "for", "not", "nahi", "hai", "mein",
             "harsh", "dev", "pal", "ira"}   # also ordinary words ("harsh words")

PATTERNS = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"), "[EMAIL]"),
    (re.compile(r"(?<!\d)(?:\+91[\s-]?)?[6-9]\d{9}(?!\d)"), "[PHONE]"),
    (re.compile(r"\b20\d{2}U[A-Z]{2}\d{4}\b", re.I), "[ROLL_NO]"),
]


@lru_cache(maxsize=1)
def known_names() -> frozenset[str]:
    with system_session() as cur:
        rows = fetch_all(cur, "SELECT lower(first_name) AS n FROM person "
                              "UNION SELECT lower(last_name) FROM person")
    return frozenset(r["n"] for r in rows if len(r["n"]) >= 3) - NOT_NAMES


def redact(text: str) -> tuple[str, dict[str, str]]:
    """Returns (redacted text, {"[PERSON_1]": "Ram Kumar", ...})."""
    for pattern, label in PATTERNS:
        text = pattern.sub(label, text)

    names = known_names()
    mapping: dict[str, str] = {}
    by_name: dict[str, str] = {}

    # runs of 1-3 name words, e.g. "Ram", "Ram Kumar", "Neha Kapoor"
    word = r"[A-Za-z][a-z]+"
    run = re.compile(rf"\b({word}(?:\s+{word}){{0,2}})\b")

    def replace(m: re.Match) -> str:
        words = m.group(1).split()
        out, i = [], 0
        while i < len(words):
            j = i
            while j < len(words) and words[j].lower() in names:
                j += 1
            if j == i:
                out.append(words[i])
                i += 1
                continue
            name = " ".join(words[i:j])
            key = by_name.get(name.lower())
            if key is None:
                key = f"[PERSON_{len(mapping) + 1}]"
                by_name[name.lower()] = key
                mapping[key] = name
            out.append(key)
            i = j
        return " ".join(out)

    text = run.sub(replace, text)
    return text, mapping


def unredact(text: str | None, mapping: dict[str, str]) -> str | None:
    if not text:
        return text
    for key, name in mapping.items():
        text = text.replace(key, name)
    return text
