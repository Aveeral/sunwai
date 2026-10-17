-- =====================================================================
--  07_security.sql : DCL - roles, GRANT / REVOKE, row-level security.
--
--  The backend logs in as one user (sunwai_app) and, for every request,
--  switches to the logged-in person's role with  SET LOCAL ROLE  and
--  sets  app.user_id.  So permissions are checked by PostgreSQL itself:
--  if a student asks for an ICC case, the DATABASE refuses.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Roles (NOLOGIN group roles, one per kind of user)
-- ---------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['sunwai_student','sunwai_handler','sunwai_triage',
                           'sunwai_icc','sunwai_antiragging','sunwai_sgrc',
                           'sunwai_ombudsperson','sunwai_admin'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
  -- the application login: may switch to any of the roles above
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sunwai_app') THEN
    CREATE ROLE sunwai_app LOGIN NOINHERIT;
  END IF;
END $$;

-- The application login's password. Locally it is 'sunwai_app_dev'; for a
-- deployment, scripts/deploy_db.sh passes a long random one (-v app_password=...).
ALTER ROLE sunwai_app PASSWORD :'app_password';

-- Everyone who handles complaints can also file their own (role inheritance)
GRANT sunwai_student TO sunwai_handler, sunwai_triage, sunwai_icc,
                        sunwai_antiragging, sunwai_sgrc, sunwai_ombudsperson;
GRANT sunwai_handler TO sunwai_icc, sunwai_antiragging, sunwai_sgrc;
GRANT sunwai_student, sunwai_handler, sunwai_triage, sunwai_icc, sunwai_antiragging,
      sunwai_sgrc, sunwai_ombudsperson, sunwai_admin TO sunwai_app;

-- ---------------------------------------------------------------------
-- 2. Start from nothing
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA sunwai FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA sunwai FROM PUBLIC;
REVOKE ALL ON SCHEMA sunwai FROM PUBLIC;

GRANT USAGE ON SCHEMA sunwai TO sunwai_student, sunwai_handler, sunwai_triage, sunwai_icc,
      sunwai_antiragging, sunwai_sgrc, sunwai_ombudsperson, sunwai_admin, sunwai_app;

-- ---------------------------------------------------------------------
-- 3. Reference data: readable by every role
-- ---------------------------------------------------------------------
GRANT SELECT ON department, category, category_requirement, committee, course,
                course_offering, exam, position
      TO sunwai_student, sunwai_admin;

-- People: name and department only (no phone / email for students)
GRANT SELECT (person_id, first_name, last_name, person_type, unit_id) ON person TO sunwai_student;
GRANT SELECT ON person, faculty, committee_member, routing_rule TO sunwai_admin;
GRANT SELECT (person_id, designation) ON faculty TO sunwai_student;

-- ---------------------------------------------------------------------
-- 4. Complaint data: SELECT is granted, but row-level security (below)
--    decides WHICH rows each person sees.
-- ---------------------------------------------------------------------
GRANT SELECT ON complaint, complaint_party, complaint_detail, ai_triage_result,
                clarification, status_history, routing_decision, conflict_exclusion,
                question_dispute, appeal, answer_script, marks_change_log, enrollment
      TO sunwai_student;
GRANT SELECT ON complaint, complaint_detail, ai_triage_result, status_history,
                routing_decision, answer_script, marks_change_log
      TO sunwai_admin;

-- Complainant identity: visible only through RLS + can_see_identity()
GRANT SELECT ON complainant_identity TO sunwai_student;
-- (sunwai_admin gets NO access to complainant_identity at all)

-- Access log: only the administrator / auditor can read it
GRANT SELECT ON access_log TO sunwai_admin;

-- ---------------------------------------------------------------------
-- 5. Column-level privileges (the DCL showcase)
--    A handler may change ONLY the status and resolution columns,
--    never the text the student wrote.
--    A complainant may only set the feedback rating.
-- ---------------------------------------------------------------------
GRANT UPDATE (status, resolution_outcome, resolution_note) ON complaint TO sunwai_handler;
GRANT UPDATE (feedback_rating) ON complaint TO sunwai_student;

-- ---------------------------------------------------------------------
-- 6. History is append-only for EVERY role (also enforced by trigger T7)
-- ---------------------------------------------------------------------
REVOKE UPDATE, DELETE ON status_history, routing_decision, conflict_exclusion,
                         access_log, marks_change_log
  FROM sunwai_student, sunwai_handler, sunwai_triage, sunwai_icc, sunwai_antiragging,
       sunwai_sgrc, sunwai_ombudsperson, sunwai_admin, sunwai_app;

-- ---------------------------------------------------------------------
-- 7. Views
-- ---------------------------------------------------------------------
GRANT SELECT ON v_complaint_overview, v_my_complaints, v_complaint_timeline TO sunwai_student;
-- the admin reads the same overview; RLS removes every sensitive complaint
GRANT SELECT ON v_complaint_overview, v_complaint_timeline TO sunwai_admin;
GRANT SELECT ON v_handler_queue   TO sunwai_handler;
GRANT SELECT ON v_committee_cases TO sunwai_icc, sunwai_antiragging, sunwai_sgrc;
GRANT SELECT ON v_icc_cases         TO sunwai_icc;
GRANT SELECT ON v_antiragging_cases TO sunwai_antiragging;
GRANT SELECT ON v_sgrc_cases        TO sunwai_sgrc;
GRANT SELECT ON v_triage_queue      TO sunwai_triage;
GRANT SELECT ON v_resolution_by_office, v_sla_breaches, v_hotspots, v_ai_accuracy,
                v_clarification_stats, v_dashboard_summary, v_weekly_trend
      TO sunwai_admin;

-- ---------------------------------------------------------------------
-- 8. Functions (procedures) each role may call
-- ---------------------------------------------------------------------
-- helpers used inside views / policies must be callable by everyone
GRANT EXECUTE ON FUNCTION app_now(), current_person_id(), person_name(int), priority_rank(text),
      conflict_label(text), latest_decision(int), can_see_complaint(int), can_see_identity(int),
      is_complainant(int,int), is_current_handler(int,int), was_handler(int,int),
      is_committee_handler(int,int), is_triage_officer(int), is_ombudsperson(int),
      is_sensitive(int), check_completeness(int),
      allowed_transition(text,text), compute_priority(text,text), default_sla_hours(text)
  TO sunwai_student, sunwai_admin;

-- complainant actions
GRANT EXECUTE ON FUNCTION file_complaint(text,text,boolean),
      record_ai_triage(int,int,text,numeric,boolean,text,jsonb,jsonb,jsonb),
      add_complaint_party(int,int,text,text,text,text),
      answer_clarification(int,int,text), find_person_candidates(text,text), my_profile(),
      rate_and_close(int,int), reopen_complaint(int,text), file_appeal(int,text),
      file_reevaluation(int,jsonb)
  TO sunwai_student;

-- opening a complaint (RLS decides; the view of a confidential case is logged)
GRANT EXECUTE ON FUNCTION open_complaint(int), log_access(int,text) TO sunwai_student, sunwai_admin;

-- handler actions
GRANT EXECUTE ON FUNCTION request_info(int,text), decide_dispute(int,int,text,numeric),
      assign_reviewer(int)
  TO sunwai_handler;

GRANT EXECUTE ON FUNCTION confirm_triage(int,int,text) TO sunwai_triage;
GRANT EXECUTE ON FUNCTION decide_appeal(int,text,text) TO sunwai_ombudsperson;
GRANT EXECUTE ON FUNCTION escalate_overdue(), close_stale_needs_info(int) TO sunwai_admin;

-- ---------------------------------------------------------------------
-- 9. Row-level security: which ROWS each person sees
-- ---------------------------------------------------------------------
ALTER TABLE complaint            ENABLE ROW LEVEL SECURITY;
ALTER TABLE complainant_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaint_party      ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaint_detail     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_triage_result     ENABLE ROW LEVEL SECURITY;
ALTER TABLE clarification        ENABLE ROW LEVEL SECURITY;
ALTER TABLE status_history       ENABLE ROW LEVEL SECURITY;
ALTER TABLE routing_decision     ENABLE ROW LEVEL SECURITY;
ALTER TABLE conflict_exclusion   ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_dispute     ENABLE ROW LEVEL SECURITY;
ALTER TABLE appeal               ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE answer_script        ENABLE ROW LEVEL SECURITY;
ALTER TABLE marks_change_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment           ENABLE ROW LEVEL SECURITY;

-- Complaint: visible if can_see_complaint() says so
-- (pg_has_role() here is evaluated as the querying role, so the
--  administrator sees non-sensitive complaints only)
CREATE POLICY complaint_read ON complaint FOR SELECT
  USING (can_see_complaint(complaint_id)
         OR (pg_has_role('sunwai_admin', 'MEMBER') AND NOT is_sensitive(complaint_id)));
-- Handler may update only complaints currently assigned to them (or their committee)
CREATE POLICY complaint_handler_update ON complaint FOR UPDATE TO sunwai_handler
  USING (is_current_handler(complaint_id) OR is_committee_handler(complaint_id));
-- Complainant may update (only the rating column, see GRANT) on their own complaints
CREATE POLICY complaint_owner_update ON complaint FOR UPDATE TO sunwai_student
  USING (is_complainant(complaint_id));

-- Identity: separate, stricter rule
CREATE POLICY identity_read ON complainant_identity FOR SELECT
  USING (can_see_identity(complaint_id));

-- Child tables follow the complaint they belong to
CREATE POLICY party_read   ON complaint_party   FOR SELECT USING (can_see_complaint(complaint_id));
CREATE POLICY detail_read  ON complaint_detail  FOR SELECT
  USING (can_see_complaint(complaint_id)
         OR (pg_has_role('sunwai_admin', 'MEMBER') AND NOT is_sensitive(complaint_id)));
CREATE POLICY ai_read      ON ai_triage_result  FOR SELECT
  USING (can_see_complaint(complaint_id)
         OR (pg_has_role('sunwai_admin', 'MEMBER') AND NOT is_sensitive(complaint_id)));
CREATE POLICY clar_read    ON clarification     FOR SELECT USING (can_see_complaint(complaint_id));
CREATE POLICY hist_read    ON status_history    FOR SELECT
  USING (can_see_complaint(complaint_id)
         OR (pg_has_role('sunwai_admin', 'MEMBER') AND NOT is_sensitive(complaint_id)));
CREATE POLICY dec_read     ON routing_decision  FOR SELECT
  USING (can_see_complaint(complaint_id)
         OR (pg_has_role('sunwai_admin', 'MEMBER') AND NOT is_sensitive(complaint_id)));
CREATE POLICY dispute_read ON question_dispute  FOR SELECT USING (can_see_complaint(complaint_id));
CREATE POLICY appeal_read  ON appeal            FOR SELECT USING (can_see_complaint(complaint_id));
CREATE POLICY marks_read   ON marks_change_log  FOR SELECT USING (can_see_complaint(complaint_id));
CREATE POLICY excl_read    ON conflict_exclusion FOR SELECT
  USING (EXISTS (SELECT 1 FROM routing_decision d
                 WHERE d.decision_id = conflict_exclusion.decision_id
                   AND can_see_complaint(d.complaint_id)));

-- Access log: administrator / auditor only
CREATE POLICY access_log_admin ON access_log FOR SELECT TO sunwai_admin USING (TRUE);

-- Answer scripts: the student who wrote it, the evaluator, the reviewer
-- of a re-evaluation of it, and the administrator
CREATE POLICY script_read ON answer_script FOR SELECT
  USING (student_id = current_person_id()
         OR evaluator_id = current_person_id()
         OR pg_has_role(current_user, 'sunwai_admin', 'MEMBER')
         OR EXISTS (SELECT 1 FROM complaint c
                    WHERE c.script_id = answer_script.script_id
                      AND can_see_complaint(c.complaint_id)));

-- Enrolment: a student sees only their own
CREATE POLICY enrollment_read ON enrollment FOR SELECT
  USING (student_id = current_person_id() OR pg_has_role(current_user, 'sunwai_admin', 'MEMBER'));
