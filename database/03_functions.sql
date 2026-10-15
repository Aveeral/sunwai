-- =====================================================================
--  03_functions.sql : helper functions used by triggers, procedures,
--  views and row-level security.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- "Current time" and "current user" for the application.
-- The backend sets  app.user_id  (the logged-in person) on every request.
-- app.now lets the demo "fast-forward" time to show SLA escalation;
-- in normal use it is empty and the real clock is used.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_now() RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('app.now', true), '')::timestamptz, now());
$$;

CREATE OR REPLACE FUNCTION current_person_id() RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.user_id', true), '')::int;
$$;

CREATE OR REPLACE FUNCTION person_name(p_person int) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN f.person_id IS NOT NULL THEN 'Dr. ' ELSE '' END
         || p.first_name || ' ' || p.last_name
  FROM person p LEFT JOIN faculty f USING (person_id)
  WHERE p.person_id = p_person;
$$;

-- ---------------------------------------------------------------------
-- Priority: max(category base priority, AI urgency).
-- The AI can RAISE the priority but never LOWER it below the category's
-- base. If the category has no base (General/Other) the AI decides.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION priority_rank(p text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 WHEN 'High' THEN 3 END;
$$;

CREATE OR REPLACE FUNCTION compute_priority(p_base text, p_ai_urgency text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
           WHEN p_base IS NULL THEN coalesce(p_ai_urgency, 'Medium')
           WHEN p_ai_urgency IS NULL THEN p_base
           WHEN priority_rank(p_ai_urgency) > priority_rank(p_base) THEN p_ai_urgency
           ELSE p_base
         END;
$$;

-- Deadline used when a category has no sla_hours of its own
CREATE OR REPLACE FUNCTION default_sla_hours(p_priority text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_priority WHEN 'High' THEN 4 WHEN 'Medium' THEN 24 ELSE 48 END;
$$;

-- ---------------------------------------------------------------------
-- Hierarchy helpers (recursive queries)
-- ---------------------------------------------------------------------

-- All positions BELOW a given position (its subordinates, at any depth)
CREATE OR REPLACE FUNCTION positions_below(p_position int)
RETURNS TABLE (position_id int)
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE sub AS (
      SELECT p.position_id FROM position p WHERE p.reports_to = p_position
    UNION
      SELECT p.position_id FROM position p JOIN sub s ON p.reports_to = s.position_id
  )
  SELECT position_id FROM sub;
$$;

-- TRUE if p_candidate holds a post that sits below a post held by p_boss.
-- Used for the "ReportsToRespondent" conflict rule.
CREATE OR REPLACE FUNCTION reports_to_person(p_candidate int, p_boss int) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM position boss_pos
    CROSS JOIN LATERAL positions_below(boss_pos.position_id) b
    JOIN position cand_pos ON cand_pos.position_id = b.position_id
    WHERE boss_pos.holder_id = p_boss
      AND cand_pos.holder_id = p_candidate
  );
$$;

-- The department chain of a unit, from the unit itself up to the root
CREATE OR REPLACE FUNCTION unit_ancestors(p_unit int)
RETURNS TABLE (unit_id int, depth int)
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE up AS (
      SELECT d.unit_id, d.parent_unit_id, 0 AS depth FROM department d WHERE d.unit_id = p_unit
    UNION ALL
      SELECT d.unit_id, d.parent_unit_id, up.depth + 1
      FROM department d JOIN up ON d.unit_id = up.parent_unit_id
  )
  SELECT unit_id, depth FROM up;
$$;

-- Find the post with a given role for a unit: first in the unit itself,
-- then up the department tree, then any post with that role (central post).
CREATE OR REPLACE FUNCTION resolve_role_position(p_role text, p_unit int) RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT pos.position_id
  FROM position pos
  LEFT JOIN unit_ancestors(p_unit) a ON a.unit_id = pos.unit_id
  WHERE pos.role_code = p_role
    AND pos.holder_id IS NOT NULL
  ORDER BY (a.depth IS NULL), a.depth, pos.position_id
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------
-- Conflict of interest.
-- Returns the reason a person must NOT handle a complaint, or NULL.
-- p_committee = TRUE adds the committee-only rule "SameDepartment".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION conflict_reason(p_person int, p_complaint int, p_committee boolean DEFAULT FALSE)
RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE
    -- 1. the person is named as a respondent
    WHEN EXISTS (SELECT 1 FROM complaint_party cp
                 WHERE cp.complaint_id = p_complaint AND cp.party_role = 'Respondent'
                   AND cp.person_id = p_person)
      THEN 'Respondent'
    -- 2. the person filed the complaint
    WHEN EXISTS (SELECT 1 FROM complainant_identity ci
                 WHERE ci.complaint_id = p_complaint AND ci.person_id = p_person)
      THEN 'Complainant'
    -- 3. re-evaluation: the person evaluated the disputed script
    WHEN EXISTS (SELECT 1 FROM complaint c JOIN answer_script s ON s.script_id = c.script_id
                 WHERE c.complaint_id = p_complaint AND s.evaluator_id = p_person)
      THEN 'OriginalEvaluator'
    -- 4. the person reports (directly or indirectly) to a respondent
    WHEN EXISTS (SELECT 1 FROM complaint_party cp
                 WHERE cp.complaint_id = p_complaint AND cp.party_role = 'Respondent'
                   AND cp.person_id IS NOT NULL
                   AND reports_to_person(p_person, cp.person_id))
      THEN 'ReportsToRespondent'
    -- 5. committee members from the respondent's own department are recused
    WHEN p_committee AND EXISTS (
                 SELECT 1 FROM complaint_party cp
                 JOIN person r ON r.person_id = cp.person_id
                 JOIN person m ON m.person_id = p_person
                 WHERE cp.complaint_id = p_complaint AND cp.party_role = 'Respondent'
                   AND r.unit_id = m.unit_id)
      THEN 'SameDepartment'
  END;
$$;

-- Readable label for a conflict reason (used in RoutingDecision.reason)
CREATE OR REPLACE FUNCTION conflict_label(p_reason text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_reason
    WHEN 'Respondent'          THEN 'is the respondent'
    WHEN 'Complainant'         THEN 'filed the complaint'
    WHEN 'OriginalEvaluator'   THEN 'evaluated the original script'
    WHEN 'ReportsToRespondent' THEN 'reports to the respondent'
    WHEN 'SameDepartment'      THEN 'is from the respondent''s department'
  END;
$$;

-- Latest routing decision of a complaint
CREATE OR REPLACE FUNCTION latest_decision(p_complaint int) RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT decision_id FROM routing_decision
  WHERE complaint_id = p_complaint
  ORDER BY decided_at DESC, decision_id DESC LIMIT 1;
$$;
