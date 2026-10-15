# The Sunwai database, explained

This is the graded core of the project, so every team member should read it. Each section says who on the team "owns" that part for the viva.

## The files, in the order they run

| File | What it does | Owner |
|---|---|---|
| `01_schema.sql` | Creates the 28 tables with every PK, FK, CHECK, UNIQUE and index | Aveeral |
| `02_seed_reference.sql` | The college structure: departments, hostels, offices, posts and who reports to whom, committees, categories, completeness rules, routing rules | Aveeral |
| `03_functions.sql` | Small helpers: priority calculation, the recursive hierarchy queries, the conflict check | Piyush |
| `04_triggers.sql` | Rules the database enforces on every change: visibility, state machine, status history, deadline pause, evaluator block, mark log, append-only history | Piyush |
| `05_procedures.sql` | The business logic: filing, AI triage, completeness check, routing, escalation, appeals, re-evaluation | Piyush (routing), Chetan (triage / completeness) |
| `06_views.sql` | Queues for each role, plus analytics | Kavya |
| `07_security.sql` | DCL: roles, GRANT/REVOKE, column privileges, row-level security | Kavya |
| `08_seed_demo.sql` | 100 students, courses, exams, and about 60 complaints created through the real procedures | Aveeral |
| `tests/*.sql` | 90 automatic checks, one or more for every rule | everyone |

`run_all.sql` runs files 01 to 08 in order. `run_tests.sql` runs every test. The tests always roll back, so the data is unchanged afterwards.

## The life of one complaint

Aarav (BH-3, room 214) writes *"washroom mein paani nahi aa raha"*.

1. **`file_complaint()`** inserts a `complaint` row (status **Filed**). His identity goes into the separate `complainant_identity` table.
   - The trigger `complaint_status_history` writes status history row 1.
2. The backend (phase 3) sends the text to the LLM and calls **`record_ai_triage()`** with the answer: category *Hostel – Water supply*, confidence 0.92, urgency Low.
   - This writes `ai_triage_result`.
   - Each extracted detail becomes a row in `complaint_detail`.
3. Confidence ≥ 0.70, so the AI's category is accepted. **`process_complaint()`** then runs four steps:
   - **`apply_context()`** works out where the complaint is (the BH-3 unit).
   - **`fill_from_profile()`** adds `hostel = BH-3` and `room_or_floor = Room 214` from his student record, marked `source = 'Profile'`.
   - **`check_completeness()`** compares the category's mandatory fields (`category_requirement`) with the details present. Nothing is missing, so the status becomes **Triaged**.
   - **`route_complaint()`** routes it.
4. **`route_complaint()`** does the following:
   - It computes the priority as max(category base *Medium*, AI urgency *Low*) = **Medium**.
   - The deadline comes from the category SLA: 24 hours.
   - The rule for this category says **Caretaker**. `resolve_role_position('Caretaker', BH-3)` finds *Caretaker BH-3* (Dinesh Kumar).
   - `conflict_reason()` checks that Dinesh Kumar has no conflict.
   - It writes a `routing_decision` with a readable reason, and sets the status to **Assigned**.
5. The caretaker moves it to **InProgress**, then **Resolved**. The trigger `complaint_validate_status` lets these through because they are allowed moves; it would block a jump straight from Assigned to Resolved.
6. Aarav rates it with **`rate_and_close()`**, and the status becomes **Closed**.

## Key ideas, and how to explain them

### "The LLM suggests, the database decides"
The AI only fills in `ai_triage_result` and `complaint_detail`. The decision about who handles a complaint comes from `routing_rule`, `position` and `conflict_reason()`. All of these are tables and SQL, so every decision is explainable and stored in `routing_decision.reason`.

Because the AI's guess (`ai_triage_result.suggested_category_id`) and the final category (`complaint.category_id`) are both stored, `v_ai_accuracy` measures how often the AI was right, using plain GROUP BY.

### Completeness check
`category_requirement` is the rulebook: for each category, which fields are needed and what question to ask. `check_completeness()` is a single query: *mandatory fields for this category that have no row in complaint_detail* (a `NOT EXISTS` anti-join). Missing fields become `clarification` rows, and the complaint waits in **NeedsInfo**.

For sensitive categories, only `respondent_role` is mandatory, and "Unknown" counts as an answer. So a harassment complaint is **never** blocked.

### Conflict of interest: the five rules (`conflict_reason()`)
1. **Respondent:** the person is named as the respondent.
2. **Complainant:** the person filed the complaint.
3. **OriginalEvaluator:** the person marked the disputed script.
4. **ReportsToRespondent:** the person sits below a respondent in the hierarchy. This uses a **recursive CTE** (`positions_below()`) that walks `position.reports_to` downward.
5. **SameDepartment:** applies to committee members only. A member from the respondent's department is recused.

For a post, `assign_up_chain()` walks **up** `reports_to` until it finds someone with no conflict. That's how *HOD CSE (respondent) → Dean Academics* happens.

For a committee, `assign_to_committee()` recuses conflicted members. If too few remain for the quorum, the case goes to the Ombudsperson. Every skip is stored in `conflict_exclusion`.

### Escalation
`escalate_overdue()` finds open complaints whose `due_at` has passed. It moves each one to the holder of the next post up (`reports_to`), re-running the conflict check, and writes a routing decision of type `Escalation`.

Academic and exam complaints go from the Dean Academics to the SGRC. While a complaint is in NeedsInfo, trigger T4 adds the waiting time to the deadline.

### Security (DCL), in three layers
1. **GRANT / REVOKE.** For example, a student has no SELECT on `v_icc_cases`, so the query fails with *permission denied for view v_icc_cases*.
2. **Column-level privileges.** A handler has `UPDATE (status, resolution_outcome, resolution_note)` only, so changing `description` fails with *permission denied*.
3. **Row-level security.** Policies on 15 tables call `can_see_complaint()`, so a student only ever gets their own rows, even with `SELECT * FROM complaint`.

On top of that:
- `complainant_identity` has its own stricter rule: hidden on anonymous complaints, and hidden for sensitive complaints unless the student consented to contact.
- `open_complaint()` writes `access_log` for every view of a confidential case.
- History tables are append-only twice over: REVOKE UPDATE/DELETE, plus a trigger that blocks it even for the owner.

The backend (phase 3) connects as `sunwai_app` and does `SET LOCAL ROLE sunwai_student` (or handler, icc, ...) for each request. So these refusals come from PostgreSQL, not from Python code.

### Procedures as SECURITY DEFINER
A student has no INSERT right on `complaint`. Instead they call `file_complaint()`, which runs with the owner's rights and checks for itself who is calling (via `app.user_id`).

This is the standard way to give users controlled write access: they can only change data the way the procedure allows.

## Likely viva questions

**Aveeral (schema, ER mapping)**
- *Why is StatusHistory a weak entity?* A history row has no meaning without its complaint, and `seq_no` only counts within one complaint. Its key is (complaint_id, seq_no).
- *How did you map ISA?* One table per subtype, sharing the supertype's key: `student.person_id` is both PK and FK to `person`.
- *Why ComplaintDetail rows instead of a JSON column?* For 1NF, values must be atomic. It also makes the completeness check a simple `NOT EXISTS` query.
- *Why is ComplainantIdentity a separate table?* So it can have its own, stricter access rule and be completely hidden on anonymous complaints.

**Piyush (routing, conflicts, triggers)**
- *How does the conflict check find subordinates?* It uses a recursive CTE over `position.reports_to` (`positions_below()`).
- *What happens if the HOD is the respondent?* `assign_up_chain()` skips the HOD, logs `Respondent` in `conflict_exclusion`, and moves up to the Dean Academics.
- *How do you stop invalid status changes?* A BEFORE UPDATE trigger checks every move against `allowed_transition()`.
- *What if a committee loses quorum after recusals?* The case is referred to the Ombudsperson.

**Kavya (DCL, views, audit)**
- *What's the difference between GRANT and row-level security?* GRANT decides which tables, columns and functions a role can use. RLS decides which rows it sees.
- *Why are the role views `security_invoker`?* So the querying person's RLS still applies through the view.
- *How can the admin see totals but not sensitive complaints?* The analytics views return only aggregates, and the RLS policy hides sensitive rows from the admin role.
- *How do you know who read a confidential case?* `open_complaint()` writes `access_log`, which is append-only and readable only by the admin.

**Chetan (triage, completeness, re-evaluation)**
- *When is the AI's category trusted?* When confidence ≥ 0.70 (or the complaint is flagged sensitive). Otherwise it waits in the triage officer's queue (`v_triage_queue`).
- *Can the AI lower a priority?* No. `compute_priority()` takes the maximum of the category base and the AI urgency.
- *How is the re-evaluation reviewer chosen?* `assign_reviewer()` picks a faculty member from the course's department with no conflict and the fewest open reviews. The original evaluator is always excluded, and trigger T5 blocks it even if someone tries manually.
- *Where are mark changes recorded?* Trigger T6 writes `marks_change_log` and updates the script total.

## Demo data you can rely on

| Complaint | What it shows |
|---|---|
| Water, BH-3 2nd floor (4 complaints) | Hotspot; routed to the BH-3 caretaker |
| Riya's harassment complaint about Dr. Ram Kumar | Goes to the ICC; Dr. Vikram Sethi (CSE) recused |
| Sneha's internal-marks complaint about the HOD of CSE | HOD skipped; goes to the Dean Academics |
| Aarav's faculty-conduct complaint about the HOD | Goes to the SGRC; Dr. Neha Kapoor (reports to the HOD) recused |
| Kabir's anonymous ragging complaint | Goes to the Anti-Ragging Committee; identity hidden |
| Ishaan's Wi-Fi complaint, 3 days old | Overdue; run `escalate_overdue()` live |
| BH-1 mess complaint | Already escalated, Warden → Chief Warden |
| Ananya's projector complaint | NeedsInfo (no room given) |
| Library hours, room theft | Waiting in the triage queue |
| Software Engineering conduct complaint | Dismissed by the SGRC, then appealed |
| Aarav's electricity complaint | Resolved yesterday; can be reopened |
| Ishaan's re-evaluation | Done; marks changed 3 → 5, logged |
| Aarav's DBMS re-evaluation | Waiting for the reviewer (Dr. Sunita Rao), not the evaluator |

**Demo logins** (person ids):

| Who | Person id |
|---|---|
| Aarav | 1001 |
| Riya | 1002 |
| Ishaan | 1003 |
| Kabir | 1005 |
| Sneha | 1006 |
| Caretaker BH-3 | 203 |
| Warden BH-3 | 167 |
| HOD CSE | 102 |
| Dean Academics | 161 |
| ICC chair | 141 |
| Recused ICC member | 103 |
| SGRC chair | 131 |
| Anti-Ragging chair | 171 |
| Triage officer | 210 |
| Ombudsperson | 172 |
| Admin (Registrar) | 209 |
