# Sunwai – AI-Routed Grievance Redressal System for NSUT

**Live site:** VERCEL-LINK-HERE  ·  [**API:** https://sunwai-nine.vercel.app]
            

Anyone at NSUT can file a complaint in plain English or Hinglish. An LLM turns it into structured details, and the **database** does the rest:

- checks the complaint is complete and asks short follow-up questions when it isn't
- sets its priority (the AI can raise it, never lower it)
- routes it to the right office or committee
- keeps away anyone with a conflict of interest
- enforces confidentiality with DCL (roles, column privileges, row-level security)
- escalates overdue complaints up the chain automatically
- handles appeals to the Ombudsperson and question-wise exam re-evaluation

**Team (CSDS, Section I):** Aveeral Jain (2025UCD2177), Kavya Gautam (2025UCD2143), Chetan Sameer (2025UCD2142), Piyush Aggarwal (2025UCD2116)

## Using the live site

1. Open the live site. The free server sleeps when unused; **the first visit can take up to a minute** (the login page says "Waking up the server").
2. Pick a person on **Log in as**. Each one gets the database role their position gives them: students, office handlers, committee members, the triage officer, the Ombudsperson, the Registrar (admin).
3. Good first steps:
   - **Aarav** → *File a complaint* → type `BH-3 washroom mein paani nahi aa raha` and watch the checklist fill in.
   - **Aarav** → *Security demo* → *Run all*, then switch to the **Registrar** and run it again.
   - **Registrar** → *Dashboard*.
4. The full 8-minute demo script is in [`docs/03_frontend_explained.md`](docs/03_frontend_explained.md#demo-walkthrough-about-8-minutes).

All data is fictional demo data. Anyone with the link can use it, so please don't type real personal details.

## Project status

| Part | Status |
|---|---|
| Database: 28 tables, triggers, procedures, views, security | ✅ 90 SQL tests |
| Backend: FastAPI, LLM triage, scheduler | ✅ 47 tests |
| Frontend: React, every role | ✅ checked end to end in a browser |
| Deployment: Neon (database), Render (API), Vercel (website) | ✅ live |

## How it fits together

```
Browser (React, Vercel)
   │  HTTPS
   ▼
FastAPI (Render)  ──►  OpenAI (names removed first)
   │  logs in as sunwai_app, then SET LOCAL ROLE <user's role> per request
   ▼
PostgreSQL (Neon): all rules, routing and permissions live here
```

## Folder layout

```
database/   the graded SQL: schema, data, triggers, procedures, views, security, tests
backend/    FastAPI app: LLM triage, login, one router per screen, tests
frontend/   React website: one screen per file in src/pages
scripts/    set up, run, test and deploy with one command each
docs/       explanations, viva notes, coverage checklist, deployment guide
```

## Running it on your own computer (Mac)

You need **PostgreSQL** (Postgres.app from https://postgresapp.com, then `sudo mkdir -p /etc/paths.d && echo /Applications/Postgres.app/Contents/Versions/latest/bin | sudo tee /etc/paths.d/postgresapp` and reopen Terminal), **Python 3.10+** and **Node.js 18+**.

```bash
cp .env.example .env               # once; add your OpenAI key (optional: without it an offline classifier is used)
bash scripts/reset_db.sh           # build the local database (run again any time to reset the data)
bash scripts/run_tests.sh          # 90 SQL checks, every line should say PASS

bash scripts/setup_backend.sh      # once
bash scripts/run_backend.sh        # API on http://localhost:8000  (try it at /docs)

bash scripts/setup_frontend.sh     # once, in a second Terminal tab
bash scripts/run_frontend.sh       # website on http://localhost:5173

bash scripts/test_backend.sh       # 47 backend checks (resets the database before and after)
```

Run each script exactly as written, one line at a time.

### Try the database security by hand

```bash
psql sunwai
```
```sql
BEGIN;
SELECT set_config('app.user_id', '1002', true);   -- act as Riya, a student
SET LOCAL ROLE sunwai_student;
SELECT complaint_id, category, status FROM sunwai.v_my_complaints;   -- only her own
SELECT * FROM sunwai.v_icc_cases;                                    -- permission denied
ROLLBACK;
```

## Documents

| File | What's in it |
|---|---|
| [`docs/01_database_explained.md`](docs/01_database_explained.md) | How the database works, plus viva questions per team member |
| [`docs/02_backend_explained.md`](docs/02_backend_explained.md) | The backend and the LLM triage, plus viva questions |
| [`docs/03_frontend_explained.md`](docs/03_frontend_explained.md) | Every screen, what database objects it uses, and the demo script |
| [`docs/04_deployment.md`](docs/04_deployment.md) | Neon, Render and Vercel step by step; resetting the live demo data |
| [`docs/coverage.md`](docs/coverage.md) | Every table and feature from the design document, mapped to code and tests |

## Before the viva

- Open the live site **5 minutes early** so the server is awake.
- For fresh demo data, run `bash scripts/deploy_db.sh "<Neon owner connection string>"` and paste the `sunwai_app` line it prints into Render's `DATABASE_URL` (see `docs/04_deployment.md`).
- Don't push code on the day of the viva: every push redeploys automatically.
- Backup plan: run it locally (above) if the internet or a service fails.
