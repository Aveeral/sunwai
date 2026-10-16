# Coverage checklist

Every item in the design document (*Sunwai – AI-Routed Grievance Redressal System for NSUT*), where it is implemented, and the test that proves it.

✅ = implemented and tested

SQL tests are in `database/tests/` (90 checks). Backend tests are in `backend/tests/` (47 checks). The website was checked end to end in a browser (file, resolve, rate, answer a question, triage, appeal, re-evaluation, refused access).

## 1. Tables (28)

The doc uses CamelCase names; PostgreSQL uses snake_case (`CommitteeMember` → `committee_member`). All are in `database/01_schema.sql`.

| # | Table (doc) | SQL table | Status |
|---|---|---|---|
| 1 | Department | `department` | ✅ |
| 2 | Person | `person` | ✅ |
| 3 | Student | `student` | ✅ |
| 4 | Faculty | `faculty` | ✅ |
| 5 | Position | `position` | ✅ |
| 6 | Committee | `committee` | ✅ |
| 7 | CommitteeMember | `committee_member` | ✅ |
| 8 | Course | `course` | ✅ |
| 9 | CourseOffering | `course_offering` | ✅ |
| 10 | Enrollment | `enrollment` | ✅ |
| 11 | Exam | `exam` | ✅ |
| 12 | AnswerScript | `answer_script` | ✅ |
| 13 | Category | `category` | ✅ |
| 14 | CategoryRequirement | `category_requirement` | ✅ |
| 15 | RoutingRule | `routing_rule` | ✅ |
| 16 | Complaint | `complaint` | ✅ |
| 17 | ComplainantIdentity | `complainant_identity` | ✅ |
| 18 | ComplaintParty | `complaint_party` | ✅ |
| 19 | ComplaintDetail | `complaint_detail` | ✅ |
| 20 | AITriageResult | `ai_triage_result` | ✅ |
| 21 | Clarification | `clarification` | ✅ |
| 22 | StatusHistory | `status_history` | ✅ |
| 23 | AccessLog | `access_log` | ✅ |
| 24 | RoutingDecision | `routing_decision` | ✅ |
| 25 | ConflictExclusion | `conflict_exclusion` | ✅ |
| 26 | Appeal | `appeal` | ✅ |
| 27 | QuestionDispute | `question_dispute` | ✅ |
| 28 | MarksChangeLog | `marks_change_log` | ✅ |

Proven by `test_schema.sql`: exactly 28 tables, 28 primary keys, composite keys on weak entities, CHECK / UNIQUE / FK rejections.

## 2. ER concepts

| Concept (doc §6) | Where | Status |
|---|---|---|
| ISA: Person → Student, Faculty | `student.person_id`, `faculty.person_id` are PK + FK to `person` | ✅ |
| Recursive: Department.parent_unit_id | `department` | ✅ |
| Recursive: Position.reports_to | `position`; walked by `positions_below()` (recursive CTE) | ✅ test_conflicts |
| Recursive: Complaint.reopened_from | `complaint`; used by `reopen_complaint()` | ✅ test_workflow |
| Weak entities: CategoryRequirement, Clarification, StatusHistory, QuestionDispute | composite PKs (owner key + partial key) | ✅ test_schema |
| M:N with attributes: CommitteeMember, Enrollment, ComplaintParty, ComplaintDetail, ConflictExclusion | junction tables | ✅ |
| 1:1: Complaint–AITriageResult, Complaint–ComplainantIdentity | UNIQUE FK / shared PK | ✅ |
| Derived attributes: hours_pending, SLA breached, AI accuracy | `v_complaint_overview` (`hours_pending`, `deadline_state`), `v_ai_accuracy` | ✅ |
| Composite attribute: name (first, last) | `person.first_name`, `person.last_name` | ✅ |
| Normalisation 1NF/2NF/3NF | details stored as rows in `complaint_detail` (no JSON lists) | ✅ |

## 3. Modules (doc §3.1)

| # | Module | Implemented in | Proven by |
|---|---|---|---|
| 1 | Organisation & People | tables 1–5, `02_seed_reference.sql` | test_routing, test_conflicts |
| 2 | Committees & Academics | tables 6–12 | test_conflicts, test_reevaluation |
| 3 | Complaint Registration | `file_complaint()`, `add_complaint_party()` | test_routing |
| 4 | AI Triage & Completeness Check | `record_ai_triage()`, `check_completeness()`, `ask_missing_questions()`, `answer_clarification()`, `fill_from_profile()`, `find_person_candidates()` | test_routing · backend `services/llm.py`, `services/triage.py` → test_triage.py, test_llm.py |
| 5 | Categories, Priority & Routing | `compute_priority()`, `route_complaint()`, `resolve_role_position()` | test_routing |
| 6 | Conflict-of-Interest Engine | `conflict_reason()`, `assign_up_chain()`, `assign_to_committee()` | test_conflicts |
| 7 | Workflow, Escalation & Appeals | triggers T2–T4, `escalate_overdue()`, `request_info()`, `close_stale_needs_info()`, `reopen_complaint()`, `file_appeal()`, `decide_appeal()` | test_workflow |
| 8 | Answer Script Review & Re-evaluation | `file_reevaluation()`, `assign_reviewer()`, `decide_dispute()`, triggers T5, T6 | test_reevaluation |
| 9 | Security, Audit & Analytics | `07_security.sql`, `open_complaint()`, analytics views | test_security |

## 4. Features (doc §2 objectives and §5 novelty)

| Feature | Implemented in | Proven by | Status |
|---|---|---|---|
| One channel for students, faculty and staff | `file_complaint()` works for any Person | test_conflicts (caretaker files a complaint) | ✅ |
| Visibility Public / Confidential / Anonymous | `complaint.visibility` + trigger T1 | test_routing, test_security | ✅ |
| Anonymous only where the category allows | trigger T1 | — (constraint raise) | ✅ |
| Sensitive complaints forced to Confidential | trigger T1, `record_ai_triage()` | test_routing #12 | ✅ |
| AI triage stored (category, urgency, confidence, sensitivity, summary) | `ai_triage_result`, `record_ai_triage()`; OpenAI call in `services/llm.py` (JSON output, validated, cached) | test_routing, test_llm.py | ✅ |
| Confident AI category auto-accepted (≥ 0.70), else triage officer | `record_ai_triage()`, `confirm_triage()`, `v_triage_queue` | test_routing #8, #9 | ✅ |
| Name redaction before the AI call | `services/redaction.py` (names from the person table, phone, e-mail, roll no.) | test_triage.py | ✅ |
| AI fallback when OpenAI is unavailable | `services/fallback.py` (English + Hinglish keywords) | test_llm.py, test_triage.py | ✅ |
| Completeness check (CategoryRequirement vs ComplaintDetail) | `check_completeness()` (one SQL query) | test_routing #10 | ✅ |
| Missing details filled from the profile | `fill_from_profile()` (source = Profile) | test_routing #1 | ✅ |
| Short follow-up questions | `ask_missing_questions()`, `clarification` | test_routing #10, #11 | ✅ |
| Live requirements checklist | `POST /api/triage/preview` builds it from `category_requirement` + profile; shown while typing on the File a complaint screen | test_triage.py | ✅ |
| Respondent role question ("student / faculty / staff / not sure") | requirement `respondent_role` in categories 11–14 | test_routing #13 | ✅ |
| Person disambiguation ("Ram") | `find_person_candidates()` (word-start match, ranked by connection); shown in the preview | test_routing #14, test_triage.py | ✅ |
| Sensitive complaints never blocked | only `respondent_role` mandatory; "Unknown" counts | test_routing #12 | ✅ |
| Priority = max(category base, AI urgency); AI can't lower | `compute_priority()` | test_routing #2 | ✅ |
| Default deadline from priority when category has none | `default_sla_hours()` | test_routing #8 | ✅ |
| Database-driven routing (rule → role → holder for that unit, or committee) | `route_complaint()`, `resolve_role_position()` | test_routing #1–#8 | ✅ |
| Routing reason stored | `routing_decision.reason` | test_routing #4 | ✅ |
| Conflict rule: Respondent | `conflict_reason()` | test_conflicts | ✅ |
| Conflict rule: ReportsToRespondent (recursive) | `reports_to_person()`, `positions_below()` | test_conflicts | ✅ |
| Conflict rule: Complainant | `conflict_reason()` | test_conflicts | ✅ |
| Conflict rule: SameDepartment (committees) | `conflict_reason(..., TRUE)` | test_conflicts | ✅ |
| Conflict rule: OriginalEvaluator | `conflict_reason()`, trigger T5 | test_conflicts, test_reevaluation | ✅ |
| Quorum re-check after recusal | `assign_to_committee()` → Ombudsperson if quorum fails | test_conflicts | ✅ |
| Status workflow enforced by trigger | trigger T2 `allowed_transition()` | test_workflow #1 | ✅ |
| Automatic status history | trigger T3 | test_workflow #2 | ✅ |
| Needs Info pauses the deadline | trigger T4 | test_workflow #4 | ✅ |
| Auto-close after 7 days without a reply | `close_stale_needs_info()` | test_workflow #7 | ✅ |
| Escalation up the chain, conflict check re-run | `escalate_overdue()` | test_workflow #5 | ✅ |
| Academic / exam: Dean Academics → SGRC | `escalate_overdue()` | test_workflow #6 | ✅ |
| Reopen once within 7 days | `reopen_complaint()` | test_workflow #8 | ✅ |
| Rate the resolution | `rate_and_close()`, `feedback_rating` | test_workflow.py | ✅ |
| Appeal to the Ombudsperson within the window | `file_appeal()`, `decide_appeal()` | test_workflow #9, #10 | ✅ |
| Re-evaluation: question-wise disputes, independent reviewer, mark log | `file_reevaluation()`, `assign_reviewer()`, `decide_dispute()`, trigger T6 | test_reevaluation | ✅ |
| DCL roles per user type | 8 roles + `sunwai_app` login | test_security | ✅ |
| Column-level GRANT (handler: status only) | `GRANT UPDATE (status, ...)` | test_security #5 | ✅ |
| Committee-only views | `v_icc_cases`, `v_antiragging_cases`, `v_sgrc_cases` | test_security #2, #6 | ✅ |
| Row-level security | 16 policies | test_security #1, #5, #6, #9 | ✅ |
| Separate ComplainantIdentity, hidden for Anonymous | `can_see_identity()` + policy | test_security #7 | ✅ |
| Access logging of confidential cases | `open_complaint()` (runs with the caller's RLS) → `log_access()` → `access_log` | test_security #8, test_security.py | ✅ |
| History tables append-only | REVOKE + trigger T7 | test_workflow #3, test_reevaluation #7, test_security #4 | ✅ |
| Analytics: resolution time per office | `v_resolution_by_office` | manual check | ✅ |
| Analytics: deadline breaches | `v_sla_breaches` | manual check | ✅ |
| Analytics: hotspots | `v_hotspots` | manual check | ✅ |
| Analytics: AI accuracy | `v_ai_accuracy` | manual check | ✅ |
| Analytics: categories needing most clarification | `v_clarification_stats` | manual check | ✅ |
| Escalation runs automatically every few minutes | `services/scheduler.py` (as `sunwai_admin`); demo clock + `POST /api/demo/escalate` | test_zz_escalation.py | ✅ |
| Every API request runs as a real DB role | `db.session()`: `SET LOCAL ROLE`, `app.user_id` | test_security.py | ✅ |
| Show DCL refusals live | `POST /api/demo/try-access` (8 fixed forbidden queries) | test_security.py | ✅ |
| UI for every role | `frontend/src/pages/` (one screen per file) | browser walkthrough | ✅ |
| Analytics with window functions | `v_resolution_by_office.speed_rank` (RANK), `v_weekly_trend` (LAG, running SUM) | dashboard | ✅ |

## 5. Complaint domains and routes (doc §3.3)

All 12 domains are rows in `category` (15 categories) and `routing_rule`, so they can be changed without altering the schema.

| Domain | Categories | First handler (rule) | Escalation (via `position.reports_to`) | Tested |
|---|---|---|---|---|
| Hostel maintenance | 1, 2, 3 | Caretaker of the hostel | → Warden → Chief Warden | ✅ |
| Mess / food | 4 | Warden of the hostel | → Chief Warden → Dean Student Welfare | ✅ (seed) |
| Building infrastructure | 5 | Estate Officer of the block | → Department Admin → HOD | ✅ |
| Lab equipment | 6 | Lab in-charge | → HOD | ✅ |
| Academic | 7, 8 | Timetable Coordinator / HOD | → Dean Academics → SGRC | ✅ |
| Exam / re-evaluation | 9 | Controller of Examinations → reviewer ≠ evaluator | → Dean Academics → SGRC | ✅ |
| Wi-Fi / IT / IMS | 10 | Computer Centre helpdesk | → Head of Computer Centre → Registrar | ✅ |
| Faculty conduct | 11 | SGRC | appeal → Ombudsperson | ✅ |
| Sexual harassment | 12 | ICC | appeal → Ombudsperson | ✅ |
| Ragging | 13 | Anti-Ragging Committee | appeal → Ombudsperson | ✅ |
| Discrimination | 14 | SGRC | appeal → Ombudsperson | ✅ (seed) |
| General / Other | 15 | Triage Officer | → Dean Student Welfare | ✅ |

## 6. Small additions beyond the doc

These are needed to make the design work. None of them changes the 28-table structure.

- Extra `role_code` values: `DeptAdmin`, `ComputerCentreStaff`, `Proctor`, `ViceChancellor`. The doc's routing table needs "Department admin" and "Computer Centre helpdesk" as posts.
- `unit_type` value `University` for the root of the department tree.
- The doc lists 12 domains; there are 15 categories because hostel maintenance is split into water, electricity, and cleaning/furniture, and academic into timetable and internal marks/attendance.
- `resolution_outcome` values `Fixed` and `InsufficientInfo`, alongside the doc's `Upheld`, `Dismissed` and `ActionTaken`.
- Phase 3 additions to the SQL: `record_ai_triage()` takes the details the student typed on the filing form (`p_user_details`, stored with source `User`); `my_profile()` lets the filing screen read the student's own hostel and room; `find_person_candidates()` matches the start of a word ("Ram" no longer finds Vikram); `open_complaint()` became SECURITY INVOKER so row-level security decides who may open a case (this also lets the administrator open non-sensitive cases), with the log write moved to `log_access()`.
