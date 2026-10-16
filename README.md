# Sunwai – AI-Routed Grievance Redressal System for NSUT

A DBMS lab project. Anyone at NSUT can file a complaint in plain English or Hinglish. An LLM turns it into structured details, and the **database** does the rest:

- checks the complaint is complete
- sets its priority
- routes it to the right office or committee
- excludes anyone with a conflict of interest
- enforces confidentiality with DCL
- escalates overdue complaints automatically

**Team (CSDS, Section I):** Aveeral Jain (2025UCD2177), Kavya Gautam (2025UCD2143), Chetan Sameer (2025UCD2142), Piyush Aggarwal (2025UCD2116)

## Project status

| Phase | Status |
|---|---|
| 1. Database structure (28 tables, seed data) | ✅ done |
| 2. Database logic (triggers, procedures, views, security, 90 tests) | ✅ done |
| 3. Backend (FastAPI) + LLM triage (47 tests) | ✅ done |
| 4. Frontend (React) | ✅ done |
| 5. Demo script, deployment | ⏳ next |

## Folder layout

```
database/   the graded SQL: schema, data, triggers, procedures, views, security, tests
docs/       explanations, coverage checklist, viva notes
scripts/    reset the database, set up / run / test the backend
backend/    FastAPI app: LLM triage, login, one endpoint per screen, tests
frontend/   React website: one screen per file in src/pages
```

## Running the database on a Mac

**1. Install PostgreSQL 16 (one time).** The easiest option is **Postgres.app** (https://postgresapp.com): download it, open it, and click *Initialize*.

Then add its tools to your PATH so `psql` works in Terminal:

```bash
sudo mkdir -p /etc/paths.d && echo /Applications/Postgres.app/Contents/Versions/latest/bin | sudo tee /etc/paths.d/postgresapp
```

Close and reopen Terminal, then check it works:

```bash
psql --version
```

With Homebrew instead:

```bash
brew install postgresql@16 && brew services start postgresql@16
```

**2. Build the database and run the tests:**

```bash
cd Sunwai
./scripts/reset_db.sh          # creates the 'sunwai' database and loads everything
./scripts/run_tests.sh         # 90 checks; every line should say PASS
```

**3. Look around:**

```bash
psql sunwai
```

Then, inside `psql`:

```sql
SET search_path TO sunwai;
SELECT * FROM v_dashboard_summary;
SELECT complaint_id, category, status, routing_reason FROM v_complaint_overview WHERE status <> 'Closed';
SELECT * FROM v_ai_accuracy;
```

**4. Try the security yourself.** These commands pretend to be Riya (person 1002) using the student role:

```sql
BEGIN;
SELECT set_config('app.user_id', '1002', true);
SET LOCAL ROLE sunwai_student;
SELECT complaint_id, category, status FROM sunwai.v_my_complaints;   -- only her own
SELECT * FROM sunwai.v_icc_cases;                                    -- permission denied
ROLLBACK;
```

## Running the backend

Needs Python 3.10 or newer (`python3 --version`). Put your settings in `.env` (copy `.env.example`); without an OpenAI key the offline classifier is used.

```bash
bash scripts/setup_backend.sh     # once
bash scripts/run_backend.sh       # http://localhost:8000/docs to try every endpoint
bash scripts/test_backend.sh      # 47 checks (resets the database before and after)
```

## Running the website

Needs Node.js 18 or newer (`node -v`). Keep the backend running in another Terminal tab.

```bash
bash scripts/setup_frontend.sh    # once
bash scripts/run_frontend.sh      # open http://localhost:5173
```

## Documents

- `docs/01_database_explained.md`: how everything works, plus likely viva questions per member
- `docs/02_backend_explained.md`: how the backend and the LLM triage work, plus viva questions
- `docs/03_frontend_explained.md`: the screens, how they map to the database, and a demo walkthrough
- `docs/coverage.md`: every table and feature from the design doc, mapped to code and tests
