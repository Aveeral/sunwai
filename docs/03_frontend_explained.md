# The Sunwai website, explained

The website is a React app. It shows each person what their **database role** lets them see and do. It never decides permissions itself: when PostgreSQL refuses something, the screen shows PostgreSQL's own message in a violet box headed *"PostgreSQL refused this"*.

Stack: **React 18 + TypeScript**, **Vite** (dev server and build), **Tailwind CSS** (styling), **React Router** (pages), **Recharts** (one chart on the dashboard), **lucide-react** (icons), font **Public Sans**.

## Folder layout

```
frontend/
  index.html              the single HTML page
  vite.config.ts          dev server; forwards /api to the backend on port 8000
  tailwind.config.js      the colour palette (ink, paper, seal, veil, priority colours)
  src/
    main.tsx              starts React
    App.tsx               the list of pages (routes)
    api/
      client.ts           the ONLY place that talks to the backend (adds the login token, turns errors into ApiError)
      types.ts            TypeScript shapes of every API response
    lib/
      auth.tsx            who is logged in; login, switch role, logout; each role's home page
      clock.tsx           the demo clock (+24 h, run escalation)
      useAsync.ts         load data on a page, with loading / error / reload
      format.ts           dates, "in 5 h", labels for fields, statuses and conflict reasons
    components/
      ui.tsx              buttons, status badge, priority bars, panels, error box, "hidden by the database" note
      Layout.tsx          sidebar (menu depends on role), demo clock, role switcher
      ComplaintTable.tsx  the clickable table used by every list
      Timeline.tsx        the complaint history
    pages/                one file per screen (below)
```

If something looks wrong on a screen, open that screen's file in `pages/`. If data is wrong, the browser's Network tab shows the `/api/...` call, and the matching backend router has the SQL.

## Screens and what they show from the database

| Screen (file) | Who | Database objects behind it |
|---|---|---|
| Log in as (`Login.tsx`) | everyone | roles worked out from `committee_member` and `position` |
| File a complaint (`FileComplaint.tsx`) | everyone except admin | `category`, `category_requirement`, `my_profile()`, `find_person_candidates()`, then `file_complaint()` + `record_ai_triage()` |
| My complaints (`MyComplaints.tsx`) | complainant | `v_my_complaints` |
| Complaint page (`ComplaintDetail.tsx`) | anyone allowed | `open_complaint()` (RLS check + access log), `v_complaint_overview`, `complaint_detail`, `complainant_identity`, `complaint_party`, `clarification`, `routing_decision`, `conflict_exclusion`, `v_complaint_timeline`, `question_dispute`, `marks_change_log`, `appeal` |
| My queue (`HandlerQueue.tsx`) | office handlers | `v_handler_queue` |
| Handled earlier (`HandlerHistory.tsx`) | office handlers | `v_complaint_overview` + `was_handler()` |
| Committee cases (`CommitteeCases.tsx`) | ICC / Anti-Ragging / SGRC | `v_icc_cases` / `v_antiragging_cases` / `v_sgrc_cases` |
| Triage queue (`TriageQueue.tsx`) | triage officer | `v_triage_queue`, `confirm_triage()` |
| Appeals (`Appeals.tsx`) | Ombudsperson | `appeal` (RLS), `decide_appeal()` |
| Answer scripts (`Scripts.tsx`) | students | `answer_script` (RLS), `file_reevaluation()` |
| Dashboard (`Dashboard.tsx`) | admin | `v_dashboard_summary`, `v_weekly_trend`, `v_hotspots`, `v_resolution_by_office`, `v_ai_accuracy`, `v_sla_breaches`, `v_clarification_stats` |
| All complaints (`AllComplaints.tsx`) | admin | `v_complaint_overview` (RLS removes sensitive cases) |
| Access log (`AccessLog.tsx`) | admin | `access_log` |
| Security demo (`SecurityDemo.tsx`) | everyone | fixed forbidden queries, run as your role |

On the complaint page, the buttons come from the database too: the backend asks `is_complainant()`, `is_current_handler()` and `is_committee_handler()`. A section the role has no GRANT for shows *"… is hidden from your role by the database"* instead of disappearing, so you can point at it in the viva.

## How the "File a complaint" screen works

1. You type. About a second after you stop, the text is sent to `POST /api/triage/preview` (`FileComplaint.tsx`, the `useEffect` with the 1.2 s timer).
2. The right side fills in from the answer:
   - the category, the priority the database will give it, and where it will go;
   - the **checklist**: one row per `category_requirement`, marked found in your text, from your profile, or missing (with a box to type it);
   - each **person** mentioned, with the database's candidates ("Teaches your course Database Management Systems"). If none is right, "Someone else" opens a **name search** over the college directory (`GET /api/people/search` → `find_person_candidates()`), or you can just say whether they are a student, faculty or staff member;
   - "What the AI saw": the redacted text.
3. Visibility: Public is disabled for sensitive complaints, and Anonymous only appears where the category allows it. The database enforces both (trigger T1); the screen just explains it.
4. **File complaint** sends `POST /api/complaints`. The result screen says whether it was assigned, needs details, or waits for the triage officer.

## Demo walkthrough (about 8 minutes)

1. **Log in as Aarav.** File *"BH-3 washroom mein paani nahi aa raha since yesterday"*. Show the hostel and room filled from his profile. File it; it goes to the caretaker.
2. **File as Aarav:** *"Ram sir from DBMS keeps sending me inappropriate messages at night"*. Show "What the AI saw" (`[PERSON_1]`), the "Did you mean Dr. Ram Kumar, teaches your course" picker, Public greyed out. File it; it goes to the ICC.
3. **Log in as Dr. Vikram Sethi (ICC).** The new case is not in his list: he is in the same department as the respondent and was recused. **Log in as Dr. Deepa Bose (ICC chair):** the case is there, and the Routing panel lists Vikram under "Kept away".
4. **Log in as the caretaker (Dinesh Kumar).** Open Aarav's water complaint, *Start working on it*, then *Mark resolved*. Back as Aarav: rate it.
5. **Escalation:** in the sidebar, press **+24 h** a few times, then **Run escalation**. Open the Wi-Fi complaint: it has moved up the chain, with the reason in the timeline.
6. **Security demo:** as Aarav, press *Run all*. Then switch to the Registrar and run again: "See who filed each complaint" is now refused, and "Erase the audit log" is refused even for the admin.
7. **Dashboard** (Registrar): hotspots, office speed ranking (a window function), AI accuracy.

Reset the data afterwards with `bash scripts/reset_db.sh`.

## Likely viva questions

- *Does the frontend enforce security?* No. It only hides menu items a role can't use. Every request runs as the user's database role, so even a hand-made request is refused by PostgreSQL, and the screen shows that message.
- *How does the page know which buttons to show?* The backend calls the same access functions the RLS policies use (`is_current_handler()` and so on) and returns them with the complaint.
- *Why is the dashboard mostly tables?* Each analytics view is a table of aggregates. One line chart (complaints per week) and one bar list (hotspots) show trends; exact numbers are easier to read in tables.
- *How does the demo clock work?* It sets `app.now` for every request. `app_now()` in the database reads it, so deadlines pass without changing any data.
