# The Sunwai backend, explained

The backend is a thin layer between the screen and PostgreSQL. It does three jobs: it talks to the LLM, it logs people in, and it calls the database's procedures. **It makes no decisions about routing, priority or permissions.** Those all happen in the database, which is the graded part.

Stack: **FastAPI** (Python web framework), **psycopg 3** (PostgreSQL driver, plain SQL, no ORM), **OpenAI** (`gpt-4o-mini`, JSON output).

## Folder layout

```
backend/
  app/
    main.py            starts the app, turns database errors into HTTP errors
    config.py          reads .env (database URL, OpenAI key, ...)
    db.py              connection pool + "run this request as person X with role Y"
    auth.py            demo login, tokens, which roles a person holds
    schemas.py         shapes of request bodies (validated before anything runs)
    routers/           one file per screen / user type
      auth_routes.py     demo users, login, me
      complaints.py      file, list, open, answer, rate, reopen, appeal, status, request-info
      handler.py         office queue and history
      committee.py       ICC / Anti-Ragging / SGRC case lists
      triage_officer.py  triage queue, confirm category
      appeals.py         Ombudsperson
      reevaluation.py    answer scripts, re-evaluation, reviewer decisions
      analytics.py       admin dashboard, access log
      demo.py            demo clock, run escalation now, "try a forbidden query"
    services/
      redaction.py       removes names / phones / e-mails before the LLM sees the text
      llm.py             the OpenAI call, validation, caching, fallback
      fallback.py        offline keyword classifier (English + Hinglish)
      triage.py          preview (checklist, candidates) and filing
      scheduler.py       runs escalate_overdue() every 5 minutes
  tests/               45 automatic checks (pytest)
  requirements.txt
```

## The most important idea: every request runs as a real database role

The backend logs in to PostgreSQL as `sunwai_app`. That login has **no privileges of its own**. For each request, `db.session()` opens a transaction and runs:

```sql
SET LOCAL search_path TO sunwai, public;
SELECT set_config('app.user_id', '1002', true);          -- who is asking
SELECT set_config('app.role', 'sunwai_student', true);   -- written to the access log
SELECT set_config('app.now', '', true);                  -- demo clock (empty = real time)
SET LOCAL ROLE sunwai_student;                           -- now act with the student's rights
```

From then on, PostgreSQL itself applies the GRANTs, the column privileges and row-level security. `LOCAL` means all of this ends with the transaction, so the next request on the same connection starts clean.

That's why the API can show the database's own error messages:

| Try | What PostgreSQL says |
|---|---|
| Student opens the handler queue | `permission denied for view v_handler_queue` |
| ICC member opens SGRC cases | `permission denied for view v_sgrc_cases` |
| Caretaker edits a complaint's text | `permission denied for table complaint` (column privilege) |
| Anyone deletes status history | `permission denied for table status_history` |
| Admin reads who filed complaints | `permission denied for table complainant_identity` |
| Student runs `SELECT count(*) FROM complaint` | allowed, but returns only their own rows (RLS) |

`main.py` maps these errors to HTTP: permission errors become **403**, and messages our procedures raise (for example "The 7-day reopen window has passed") become **400**.

The role name is checked against a fixed whitelist before it goes into `SET ROLE`, so it can never be injected.

## Filing a complaint: preview, then file

**Step 1. `POST /api/triage/preview`**
1. `redaction.redact()` replaces names (matched against the `person` table), phone numbers, e-mails and roll numbers with placeholders:
   *"Ram sir keeps messaging me"* → *"[PERSON_1] sir keeps messaging me"*.
2. `llm.analyze()` sends the redacted text plus the list of categories and their required fields. It gets back JSON: category, confidence, urgency, sensitive, summary, details, people.
3. The answer is **validated** (pydantic). Invalid values are corrected (e.g. `"high"` → `High`, an unknown role → `Unknown`, an unknown category → General). If the call fails or the answer is garbage, the **offline classifier** is used instead, so the demo never breaks.
4. For each `[PERSON_n]`, the backend asks the database `find_person_candidates('Ram', 'Faculty')`. That returns *Dr. Ram Kumar, teaches your DBMS course* first, and *Dr. Ramesh Kumar* second.
5. It builds the **live checklist**. For each `category_requirement` it shows whether the value was found by the AI, comes from the student's profile (`my_profile()`), or is missing (with the stored question). It also shows the priority the database will compute (`compute_priority()`) and who will handle it.

Nothing is stored yet. The analysis is kept in memory for an hour under an `analysis_id`.

**Step 2. `POST /api/complaints`**
The student fills in what's missing and picks the right person. Then, in **one transaction** as the student:

```sql
SELECT file_complaint(text, visibility, contact_consent);
SELECT record_ai_triage(id, category, urgency, confidence, sensitive, summary,
                        ai_details, parties, user_details);
```

`record_ai_triage()` then runs the whole database pipeline: completeness check → priority → routing → conflict check. It returns `Assigned`, `NeedsInfo` (follow-up questions created) or `AwaitingTriage` (the triage officer must confirm).

## The LLM part

- **Model:** `gpt-4o-mini` by default (`OPENAI_MODEL` in `.env`). It uses `temperature 0` and JSON mode.
- **The prompt** (`llm.build_prompt`) is built **from the database**: the category list and the required fields come from `category` and `category_requirement`. Adding a category to the table changes what the AI is told, with no code change.
- **Urgency rules** are in the prompt: safety risks, harassment, ragging, discrimination and faculty conduct are High; things that block daily life are Medium; slow Wi-Fi is Low. The database then takes max(category base, AI urgency), so the AI can raise a priority but never lower it.
- **Cache:** every answer is saved in `backend/llm_cache/` (not committed). The same complaint gives the same answer in the demo, at no cost.
- **Cost:** about 1,500 tokens per complaint, which is roughly ₹0.02 with gpt-4o-mini.
- **Engine shown in the response** (`engine`): `gpt-4o-mini`, `gpt-4o-mini (cached)`, `offline`, or `offline (LLM unavailable)`.

## Background job

`scheduler.py` calls `escalate_overdue()` and `close_stale_needs_info(7)` every `SCHEDULER_SECONDS` (default 300), as the admin role. All the logic is in those procedures.

For the demo, `POST /api/demo/clock {"advance_hours": 72}` moves the database's idea of "now" forward (only `app_now()` sees it). Then `POST /api/demo/escalate` runs the job immediately, and you can watch an overdue Wi-Fi complaint jump from the helpdesk to the head of the Computer Centre.

## Running it on the Mac

```bash
bash scripts/setup_backend.sh     # once: creates backend/.venv, installs packages (needs Python 3.10+)
bash scripts/run_backend.sh       # starts http://localhost:8000
```

Open **http://localhost:8000/docs**. FastAPI generates a page where you can try every endpoint:
1. `POST /api/login` with `{"person_id": 1001}`, then copy the token.
2. Click **Authorize** and paste the token.
3. Call `POST /api/triage/preview` with any complaint text.

Tests (reset the database, run 46 checks offline, reset again):

```bash
bash scripts/test_backend.sh
```

## Likely viva questions

**Aveeral (overall design)**
- *Why no ORM?* The project is about SQL. Every query is visible plain SQL, and the business logic is in procedures, so an ORM would only hide it.
- *Where are the business rules?* In PostgreSQL. The backend calls `file_complaint`, `record_ai_triage`, `request_info` and so on. If you deleted the backend and called the procedures from `psql`, everything would still work, including security.
- *How do you know who is logged in?* The demo login gives an HMAC-signed token `person.role.signature`. The roles a person may use are read from the database (committee membership, posts held).

**Piyush (routing, escalation)**
- *Who runs escalation?* A background task in the backend calls `escalate_overdue()` every 5 minutes. The procedure decides what to escalate and where.
- *How do you demo it without waiting 3 days?* The demo clock sets `app.now`. `app_now()` reads it, so deadlines pass "instantly" without changing any data.

**Kavya (security)**
- *Can the backend bypass your security?* No. It connects as `sunwai_app`, which has no privileges, and switches to the user's role for every request. A bug in Python cannot show a student someone else's complaint, because PostgreSQL filters the rows.
- *Why did you make `open_complaint()` SECURITY INVOKER?* So that "may this person open this case?" is answered by the same row-level security policies as every other query. Only writing the access log runs with definer rights (`log_access()`).
- *Is the role name safe to put in `SET ROLE`?* Yes. It comes from a signed token and is checked against a whitelist, then quoted as an identifier.

**Chetan (AI triage)**
- *What does the AI decide?* Nothing final. It suggests a category, urgency and details. The database checks completeness, computes the priority and routes. Below 0.70 confidence, a human (the triage officer) confirms.
- *What if OpenAI is down or returns nonsense?* The answer is validated. On any error, the offline keyword classifier answers in the same format.
- *Privacy?* Names, phone numbers, e-mails and roll numbers are replaced before the text leaves the server. The model sees `[PERSON_1]`, and the backend maps it back and asks the database for real candidates.
- *Hinglish?* The prompt says students write in Hinglish, and the offline classifier has Hinglish keywords (paani, bijli, khana, ...).
