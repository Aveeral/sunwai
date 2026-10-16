-- =====================================================================
--  06_views.sql
--  * Role views use security_invoker = true, so the row-level security
--    policies of the person querying still apply (a student only ever
--    sees their own rows, even through a view).
--  * Analytics views run with the owner's rights but return only
--    aggregated numbers, never complaint text or identities.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Current state of every complaint (latest decision, deadline, derived
-- attributes hours_pending and deadline_state).  Base for the other views.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_complaint_overview WITH (security_invoker = true) AS
SELECT c.complaint_id,
       c.description,
       c.visibility,
       c.status,
       c.priority,
       c.filed_at,
       c.category_id,
       cat.name   AS category,
       cat.domain,
       cat.sensitivity,
       c.unit_id,
       u.name     AS unit,
       c.location_text,
       c.resolution_outcome,
       c.resolution_note,
       c.resolved_at,
       c.feedback_rating,
       c.reopened_from,
       ai.summary AS ai_summary,
       ai.confidence AS ai_confidence,
       d.decision_id,
       d.decision_type,
       d.reason   AS routing_reason,
       d.assigned_person_id,
       person_name(d.assigned_person_id) AS assigned_person,
       d.assigned_committee_id,
       com.name   AS assigned_committee,
       d.due_at,
       -- derived attributes
       round(extract(epoch FROM (coalesce(c.resolved_at, app_now()) - c.filed_at)) / 3600, 1)
                  AS hours_pending,
       CASE
         WHEN c.status IN ('Resolved','Closed','Rejected') THEN 'Done'
         WHEN c.status = 'NeedsInfo'                       THEN 'Paused'
         WHEN d.due_at IS NULL                             THEN 'NotRouted'
         WHEN d.due_at < app_now()                         THEN 'Overdue'
         WHEN d.due_at < app_now() + interval '6 hours'    THEN 'DueSoon'
         ELSE 'OnTrack'
       END AS deadline_state
FROM complaint c
LEFT JOIN category  cat ON cat.category_id = c.category_id
LEFT JOIN department u  ON u.unit_id = c.unit_id
LEFT JOIN ai_triage_result ai ON ai.complaint_id = c.complaint_id
LEFT JOIN routing_decision d  ON d.decision_id = latest_decision(c.complaint_id)
LEFT JOIN committee com       ON com.committee_id = d.assigned_committee_id;

-- ---------------------------------------------------------------------
-- 1. Student / faculty / staff : my own complaints
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_my_complaints WITH (security_invoker = true) AS
SELECT o.complaint_id, o.description, o.visibility, o.status, o.priority, o.filed_at,
       o.category, o.domain, o.unit, o.location_text,
       coalesce(o.assigned_committee, o.assigned_person) AS handled_by,
       o.due_at, o.deadline_state, o.resolution_outcome, o.resolution_note,
       o.resolved_at, o.feedback_rating, o.reopened_from,
       (SELECT count(*) FROM clarification q
        WHERE q.complaint_id = o.complaint_id AND q.answer IS NULL) AS open_questions
FROM v_complaint_overview o
JOIN complainant_identity ci ON ci.complaint_id = o.complaint_id
WHERE ci.person_id = current_person_id();

-- ---------------------------------------------------------------------
-- 2. Handler queue : open complaints assigned to me, most urgent first
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_handler_queue WITH (security_invoker = true) AS
SELECT o.complaint_id, o.category, o.domain, o.priority, o.status, o.unit, o.location_text,
       o.ai_summary, o.filed_at, o.due_at, o.deadline_state, o.hours_pending,
       o.decision_type, o.routing_reason
FROM v_complaint_overview o
WHERE o.assigned_person_id = current_person_id()
  AND o.status NOT IN ('Resolved','Closed','Rejected','Appealed')
ORDER BY (o.deadline_state = 'Overdue') DESC, priority_rank(o.priority) DESC, o.due_at;

-- ---------------------------------------------------------------------
-- 3. Committee cases : one view per committee, with recusals listed
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_committee_cases WITH (security_invoker = true) AS
SELECT o.complaint_id, com.committee_type, o.assigned_committee AS committee,
       o.category, o.priority, o.status, o.ai_summary, o.filed_at, o.due_at,
       o.deadline_state, o.routing_reason,
       (SELECT string_agg(person_name(x.person_id) || ' - ' || conflict_label(x.reason_code), '; ')
        FROM conflict_exclusion x WHERE x.decision_id = o.decision_id) AS recused_members
FROM v_complaint_overview o
JOIN committee com ON com.committee_id = o.assigned_committee_id
WHERE o.status NOT IN ('Closed');

CREATE OR REPLACE VIEW v_icc_cases WITH (security_invoker = true) AS
  SELECT * FROM v_committee_cases WHERE committee_type = 'ICC';
CREATE OR REPLACE VIEW v_antiragging_cases WITH (security_invoker = true) AS
  SELECT * FROM v_committee_cases WHERE committee_type = 'AntiRagging';
CREATE OR REPLACE VIEW v_sgrc_cases WITH (security_invoker = true) AS
  SELECT * FROM v_committee_cases WHERE committee_type = 'SGRC';

-- ---------------------------------------------------------------------
-- 4. Triage queue : complaints the AI was not confident about, and
--    General / Other complaints
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_triage_queue WITH (security_invoker = true) AS
SELECT c.complaint_id, c.description, c.filed_at, c.status, c.visibility,
       ai.suggested_category_id, sc.name AS ai_suggested_category,
       ai.confidence, ai.urgency, ai.sensitivity_flag, ai.summary
FROM complaint c
LEFT JOIN ai_triage_result ai ON ai.complaint_id = c.complaint_id
LEFT JOIN category sc ON sc.category_id = ai.suggested_category_id
WHERE (c.category_id IS NULL AND c.status = 'Filed')
   OR (c.category_id = 15 AND c.status NOT IN ('Resolved','Closed','Rejected'))
ORDER BY ai.sensitivity_flag DESC NULLS LAST, priority_rank(ai.urgency) DESC NULLS LAST, c.filed_at;

-- ---------------------------------------------------------------------
-- 5. Timeline of one complaint (status changes, routing, questions)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_complaint_timeline WITH (security_invoker = true) AS
SELECT h.complaint_id, h.changed_at AS at, 'Status' AS kind,
       coalesce(h.old_status || ' -> ', '') || h.new_status AS title, h.note AS detail
FROM status_history h
UNION ALL
SELECT d.complaint_id, d.decided_at, 'Routing',
       d.decision_type || ': ' || coalesce(person_name(d.assigned_person_id),
              (SELECT name FROM committee WHERE committee_id = d.assigned_committee_id)),
       d.reason
FROM routing_decision d
UNION ALL
SELECT q.complaint_id, q.asked_at, 'Question', q.question,
       coalesce('Answer: ' || q.answer, 'Waiting for reply')
FROM clarification q;

-- =====================================================================
--  ANALYTICS (aggregates only; for the administrator dashboard)
-- =====================================================================

-- Resolution time and deadline performance per office / post
CREATE OR REPLACE VIEW v_resolution_by_office AS
WITH first_handler AS (
  SELECT DISTINCT ON (d.complaint_id) d.complaint_id,
         coalesce(pos.title, com.name) AS office
  FROM routing_decision d
  LEFT JOIN position pos ON pos.holder_id = d.assigned_person_id
       AND pos.position_id = (SELECT p2.position_id FROM position p2
                              WHERE p2.holder_id = d.assigned_person_id
                              ORDER BY p2.position_id LIMIT 1)
  LEFT JOIN committee com ON com.committee_id = d.assigned_committee_id
  ORDER BY d.complaint_id, d.decided_at
)
SELECT f.office,
       count(*)                                                         AS complaints,
       count(*) FILTER (WHERE c.status IN ('Resolved','Closed'))        AS resolved,
       round(avg(extract(epoch FROM (c.resolved_at - c.filed_at)) / 3600)
             FILTER (WHERE c.resolved_at IS NOT NULL), 1)               AS avg_hours_to_resolve,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM routing_decision e
                        WHERE e.complaint_id = c.complaint_id
                          AND e.decision_type = 'Escalation'))          AS escalated,
       -- window function: rank offices by speed (fastest = 1)
       rank() OVER (ORDER BY avg(extract(epoch FROM (c.resolved_at - c.filed_at)) / 3600)
                    FILTER (WHERE c.resolved_at IS NOT NULL) NULLS LAST)  AS speed_rank
FROM first_handler f JOIN complaint c USING (complaint_id)
GROUP BY f.office
ORDER BY complaints DESC;

-- Complaints that missed (or are missing) their deadline
CREATE OR REPLACE VIEW v_sla_breaches AS
SELECT cat.domain,
       count(*) AS total,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM routing_decision e
                        WHERE e.complaint_id = c.complaint_id
                          AND e.decision_type = 'Escalation')
                     OR (c.status NOT IN ('Resolved','Closed','Rejected')
                         AND (SELECT due_at FROM routing_decision
                              WHERE decision_id = latest_decision(c.complaint_id)) < app_now()))
             AS breached,
       round(100.0 * count(*) FILTER (WHERE EXISTS (SELECT 1 FROM routing_decision e
                        WHERE e.complaint_id = c.complaint_id
                          AND e.decision_type = 'Escalation')) / count(*), 1) AS breach_pct
FROM complaint c JOIN category cat USING (category_id)
GROUP BY cat.domain
ORDER BY breached DESC;

-- Hotspots: units with the most repeat non-sensitive complaints
CREATE OR REPLACE VIEW v_hotspots AS
SELECT u.name AS unit, cat.domain, count(*) AS complaints,
       count(*) FILTER (WHERE c.filed_at > app_now() - interval '30 days') AS last_30_days
FROM complaint c
JOIN department u ON u.unit_id = c.unit_id
JOIN category cat USING (category_id)
WHERE cat.sensitivity = 'Normal'
GROUP BY u.name, cat.domain
HAVING count(*) >= 2
ORDER BY complaints DESC;

-- AI accuracy: how often the AI's category matched the final category
CREATE OR REPLACE VIEW v_ai_accuracy AS
SELECT cat.name AS final_category,
       count(*) AS triaged,
       count(*) FILTER (WHERE ai.suggested_category_id = c.category_id) AS ai_correct,
       round(100.0 * count(*) FILTER (WHERE ai.suggested_category_id = c.category_id)
             / count(*), 1) AS accuracy_pct,
       round(avg(ai.confidence), 2) AS avg_confidence,
       count(*) FILTER (WHERE ai.reviewed_by IS NOT NULL) AS human_reviewed
FROM ai_triage_result ai
JOIN complaint c USING (complaint_id)
JOIN category cat ON cat.category_id = c.category_id
GROUP BY cat.name
ORDER BY triaged DESC;

-- Which categories most often needed follow-up questions
CREATE OR REPLACE VIEW v_clarification_stats AS
SELECT cat.name AS category,
       count(DISTINCT c.complaint_id) AS complaints,
       count(DISTINCT q.complaint_id) AS needed_clarification,
       round(100.0 * count(DISTINCT q.complaint_id) / count(DISTINCT c.complaint_id), 1) AS pct,
       count(q.*) AS questions_asked
FROM complaint c
JOIN category cat USING (category_id)
LEFT JOIN clarification q ON q.complaint_id = c.complaint_id
GROUP BY cat.name
ORDER BY pct DESC;

-- One-row summary for the dashboard header
CREATE OR REPLACE VIEW v_dashboard_summary AS
SELECT count(*)                                                       AS total_complaints,
       count(*) FILTER (WHERE status NOT IN ('Resolved','Closed','Rejected')) AS open_complaints,
       count(*) FILTER (WHERE status = 'Escalated')                   AS escalated_now,
       count(*) FILTER (WHERE status = 'NeedsInfo')                   AS waiting_for_info,
       round(avg(extract(epoch FROM (resolved_at - filed_at)) / 3600)
             FILTER (WHERE resolved_at IS NOT NULL), 1)               AS avg_hours_to_resolve,
       round(avg(feedback_rating), 2)                                 AS avg_rating
FROM complaint;

-- Complaints per domain per week (for the trend chart)
-- Window functions: change from the previous week and running total per domain
CREATE OR REPLACE VIEW v_weekly_trend AS
SELECT date_trunc('week', c.filed_at)::date AS week, cat.domain, count(*) AS complaints,
       count(*) - lag(count(*)) OVER w AS change_vs_last_week,
       sum(count(*)) OVER w            AS running_total
FROM complaint c JOIN category cat USING (category_id)
GROUP BY 1, 2
WINDOW w AS (PARTITION BY cat.domain ORDER BY date_trunc('week', c.filed_at)::date)
ORDER BY 1, 2;
