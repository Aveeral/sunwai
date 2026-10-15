-- =====================================================================
--  05_procedures.sql : the business logic of Sunwai, as stored functions
--  (PostgreSQL "procedures").  They run as SECURITY DEFINER so a student
--  can file a complaint without needing INSERT rights on the tables;
--  each function checks for itself who is allowed to call it.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- =====================================================================
-- A. ACCESS CHECKS  (also used by row-level security in 07_security.sql)
-- =====================================================================

CREATE OR REPLACE FUNCTION is_complainant(p_complaint int, p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (SELECT 1 FROM complainant_identity
                 WHERE complaint_id = p_complaint AND person_id = p_person);
$$;

-- currently responsible handler (person in the latest routing decision)
CREATE OR REPLACE FUNCTION is_current_handler(p_complaint int, p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (SELECT 1 FROM routing_decision
                 WHERE decision_id = latest_decision(p_complaint)
                   AND assigned_person_id = p_person);
$$;

-- anyone who was ever assigned (may still view the case)
CREATE OR REPLACE FUNCTION was_handler(p_complaint int, p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (SELECT 1 FROM routing_decision
                 WHERE complaint_id = p_complaint AND assigned_person_id = p_person);
$$;

-- active member of the committee currently handling the complaint,
-- and NOT recused from it
CREATE OR REPLACE FUNCTION is_committee_handler(p_complaint int, p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM routing_decision d
    JOIN committee_member m ON m.committee_id = d.assigned_committee_id
    WHERE d.decision_id = latest_decision(p_complaint)
      AND m.person_id = p_person
      AND m.term_start <= app_now()::date
      AND (m.term_end IS NULL OR m.term_end >= app_now()::date)
      AND NOT EXISTS (SELECT 1 FROM conflict_exclusion x
                      WHERE x.decision_id = d.decision_id AND x.person_id = p_person));
$$;

CREATE OR REPLACE FUNCTION is_triage_officer(p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (SELECT 1 FROM position WHERE role_code = 'TriageOfficer' AND holder_id = p_person);
$$;

CREATE OR REPLACE FUNCTION is_ombudsperson(p_person int DEFAULT current_person_id())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT EXISTS (SELECT 1 FROM committee_member m JOIN committee c USING (committee_id)
                 WHERE c.committee_type = 'Ombudsperson' AND m.person_id = p_person);
$$;

CREATE OR REPLACE FUNCTION is_sensitive(p_complaint int)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT coalesce((SELECT cat.sensitivity = 'Sensitive'
                   FROM complaint c JOIN category cat USING (category_id)
                   WHERE c.complaint_id = p_complaint), FALSE)
      OR coalesce((SELECT sensitivity_flag FROM ai_triage_result
                   WHERE complaint_id = p_complaint), FALSE);
$$;

-- Who may SEE a complaint at all (row-level security uses this)
CREATE OR REPLACE FUNCTION can_see_complaint(p_complaint int)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_me int := current_person_id();
BEGIN
  IF v_me IS NULL THEN RETURN FALSE; END IF;
  IF is_complainant(p_complaint, v_me) THEN RETURN TRUE; END IF;
  IF was_handler(p_complaint, v_me) THEN RETURN TRUE; END IF;
  IF is_committee_handler(p_complaint, v_me) THEN RETURN TRUE; END IF;
  -- triage officer: complaints still waiting for a category
  IF is_triage_officer(v_me) AND EXISTS (
       SELECT 1 FROM complaint WHERE complaint_id = p_complaint
         AND (category_id IS NULL OR category_id = 15)) THEN
    RETURN TRUE;
  END IF;
  -- Ombudsperson: complaints under appeal
  IF is_ombudsperson(v_me) AND EXISTS (SELECT 1 FROM appeal WHERE complaint_id = p_complaint) THEN
    RETURN TRUE;
  END IF;
  -- (the administrator's access to non-sensitive complaints is granted in
  --  the row-level security policy itself, see 07_security.sql, because
  --  inside this SECURITY DEFINER function current_user is the owner)
  RETURN FALSE;
END $$;

-- Who may see WHO FILED a complaint
--   Anonymous           -> nobody except the complainant
--   Sensitive category  -> handlers only if the complainant consented to contact
--   otherwise           -> anyone handling the complaint
--   (the administrator has no GRANT on complainant_identity at all)
CREATE OR REPLACE FUNCTION can_see_identity(p_complaint int)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT is_complainant(p_complaint)
      OR EXISTS (
           SELECT 1 FROM complaint c JOIN complainant_identity ci USING (complaint_id)
           WHERE c.complaint_id = p_complaint
             AND c.visibility <> 'Anonymous'
             AND (NOT is_sensitive(p_complaint) OR ci.contact_consent)
             AND (was_handler(p_complaint) OR is_committee_handler(p_complaint)
                  OR is_ombudsperson()));
$$;

-- =====================================================================
-- B. FILING AND AI TRIAGE
-- =====================================================================

-- File a new complaint (status Filed). Returns the complaint id.
CREATE OR REPLACE FUNCTION file_complaint(p_description text,
                                          p_visibility text DEFAULT 'Public',
                                          p_contact_consent boolean DEFAULT TRUE)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_me int := current_person_id();
  v_id int;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'No logged-in user (app.user_id is not set)'; END IF;
  INSERT INTO complaint (description, visibility, filed_at)
  VALUES (p_description, p_visibility, app_now())
  RETURNING complaint_id INTO v_id;
  INSERT INTO complainant_identity (complaint_id, person_id, contact_consent)
  VALUES (v_id, v_me, p_contact_consent);
  RETURN v_id;
END $$;

-- Store the LLM's structured output.
--   p_details : {"hostel":"BH-3","room_or_floor":"2nd floor", ...}
--   p_parties : [{"person_id":101,"party_role":"Respondent","stated_role":"Faculty"}, ...]
-- The AI's category is accepted automatically only when it is confident
-- (>= 0.70) and not General/Other; otherwise a triage officer confirms it.
CREATE OR REPLACE FUNCTION record_ai_triage(p_complaint int, p_category int, p_urgency text,
                                            p_confidence numeric, p_sensitive boolean,
                                            p_summary text,
                                            p_details jsonb DEFAULT '{}'::jsonb,
                                            p_parties jsonb DEFAULT '[]'::jsonb)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_key text; v_val text; v_party jsonb;
BEGIN
  IF NOT (is_complainant(p_complaint) OR current_person_id() IS NULL) THEN
    RAISE EXCEPTION 'Only the complainant''s session can record triage for complaint %', p_complaint;
  END IF;

  INSERT INTO ai_triage_result (complaint_id, suggested_category_id, urgency, confidence,
                                sensitivity_flag, summary)
  VALUES (p_complaint, p_category, p_urgency, p_confidence, p_sensitive, p_summary);

  FOR v_key, v_val IN SELECT key, value FROM jsonb_each_text(p_details) LOOP
    IF v_val IS NOT NULL AND length(trim(v_val)) > 0 THEN
      INSERT INTO complaint_detail (complaint_id, field_name, value, source)
      VALUES (p_complaint, v_key, left(v_val, 200), 'AI')
      ON CONFLICT (complaint_id, field_name) DO NOTHING;
    END IF;
  END LOOP;

  FOR v_party IN SELECT * FROM jsonb_array_elements(p_parties) LOOP
    PERFORM add_complaint_party(p_complaint,
                                nullif(v_party->>'person_id','')::int,
                                coalesce(v_party->>'party_role','Respondent'),
                                coalesce(v_party->>'stated_role','Unknown'),
                                v_party->>'description', 'AI');
  END LOOP;

  -- a sensitive complaint is never left Public
  IF p_sensitive THEN
    UPDATE complaint SET visibility = 'Confidential'
    WHERE complaint_id = p_complaint AND visibility = 'Public';
  END IF;

  IF (p_confidence >= 0.70 OR p_sensitive) AND p_category IS NOT NULL AND p_category <> 15 THEN
    UPDATE complaint SET category_id = p_category WHERE complaint_id = p_complaint;
  END IF;

  RETURN process_complaint(p_complaint);
END $$;

-- Record a person named in the complaint; also fills the matching details
-- (respondent_role / respondent_identity) used by the completeness check.
CREATE OR REPLACE FUNCTION add_complaint_party(p_complaint int, p_person int, p_party_role text,
                                               p_stated_role text DEFAULT 'Unknown',
                                               p_description text DEFAULT NULL,
                                               p_source text DEFAULT 'User')
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_no int;
  v_role text := p_stated_role;
BEGIN
  IF p_person IS NOT NULL AND v_role = 'Unknown' THEN
    SELECT person_type INTO v_role FROM person WHERE person_id = p_person;
  END IF;
  INSERT INTO complaint_party (complaint_id, person_id, party_role, stated_role, description)
  VALUES (p_complaint, p_person, p_party_role, v_role, p_description)
  RETURNING party_no INTO v_no;

  IF p_party_role = 'Respondent' THEN
    INSERT INTO complaint_detail (complaint_id, field_name, value, source)
    VALUES (p_complaint, 'respondent_role', v_role, p_source)
    ON CONFLICT (complaint_id, field_name) DO UPDATE
      SET value = EXCLUDED.value, source = EXCLUDED.source
      WHERE complaint_detail.value = 'Unknown';
    IF p_person IS NOT NULL OR p_description IS NOT NULL THEN
      INSERT INTO complaint_detail (complaint_id, field_name, value, source)
      VALUES (p_complaint, 'respondent_identity',
              coalesce(person_name(p_person), p_description), p_source)
      ON CONFLICT (complaint_id, field_name) DO NOTHING;
    END IF;
  END IF;
  RETURN v_no;
END $$;

-- Work out WHERE the complaint is (unit) and WHICH course, from the details.
CREATE OR REPLACE FUNCTION apply_context(p_complaint int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  c        complaint%ROWTYPE;
  v_domain text;
  v_me     int;
  v_text   text;
  v_unit   int;
  v_course text;
  v_off    int;
BEGIN
  SELECT * INTO c FROM complaint WHERE complaint_id = p_complaint;
  SELECT domain INTO v_domain FROM category WHERE category_id = c.category_id;
  SELECT person_id INTO v_me FROM complainant_identity WHERE complaint_id = p_complaint;

  -- 1. a hostel named in the details
  SELECT d.unit_id INTO v_unit
  FROM complaint_detail cd JOIN department d
    ON d.unit_type = 'Hostel'
   AND regexp_replace(lower(cd.value), '[^a-z0-9]', '', 'g')
       LIKE '%' || regexp_replace(lower(d.name), '[^a-z0-9]', '', 'g') || '%'
  WHERE cd.complaint_id = p_complaint AND cd.field_name = 'hostel'
  LIMIT 1;

  -- 2. a course named in the details -> its offering and department
  SELECT value INTO v_course FROM complaint_detail
  WHERE complaint_id = p_complaint AND field_name = 'course';
  IF v_course IS NOT NULL AND c.offering_id IS NULL THEN
    SELECT o.offering_id INTO v_off
    FROM course_offering o JOIN course co USING (course_code)
    LEFT JOIN enrollment e ON e.offering_id = o.offering_id AND e.student_id = v_me
    WHERE lower(v_course) LIKE '%' || lower(co.course_code) || '%'
       OR lower(co.title) LIKE '%' || lower(v_course) || '%'
       OR lower(v_course) LIKE '%' || lower(co.title) || '%'
    ORDER BY (e.student_id IS NULL), o.offering_id
    LIMIT 1;
    IF v_off IS NOT NULL THEN
      UPDATE complaint SET offering_id = v_off WHERE complaint_id = p_complaint;
      IF v_unit IS NULL THEN
        SELECT co.unit_id INTO v_unit FROM course_offering o JOIN course co USING (course_code)
        WHERE o.offering_id = v_off;
      END IF;
    END IF;
  END IF;

  -- 3. a building / lab named in the details -> that department's block
  IF v_unit IS NULL THEN
    SELECT string_agg(value, ' ') INTO v_text FROM complaint_detail
    WHERE complaint_id = p_complaint AND field_name IN ('building_room','lab_name','location');
    v_text := lower(coalesce(v_text, ''));
    v_unit := CASE
      WHEN v_text ~ '\m(cse|computer science)' THEN 2
      WHEN v_text ~ '\m(it|information technology)\M' THEN 3
      WHEN v_text ~ '\m(ece|electronics)' THEN 4
      WHEN v_text ~ '\m(me|mech|mechanical)' THEN 5
      WHEN v_text ~ '\m(maths?|mathematics)' THEN 6
      WHEN v_text ~ '\m(civil)' THEN 7
    END;
  END IF;

  -- 4. fall back to the complainant's own hostel / department
  IF v_unit IS NULL THEN
    IF v_domain IN ('Hostel','Mess') THEN
      SELECT hostel_unit_id INTO v_unit FROM student WHERE person_id = v_me;
    END IF;
    IF v_unit IS NULL THEN
      SELECT unit_id INTO v_unit FROM person WHERE person_id = v_me;
    END IF;
  END IF;

  UPDATE complaint
     SET unit_id = coalesce(unit_id, v_unit),
         location_text = coalesce(location_text,
            (SELECT string_agg(value, ', ' ORDER BY field_name) FROM complaint_detail
              WHERE complaint_id = p_complaint
                AND field_name IN ('hostel','room_or_floor','building_room','lab_name','location')))
   WHERE complaint_id = p_complaint;
END $$;

-- Fill missing details from the complainant's profile (e.g. their hostel
-- and room). Marked source = 'Profile' so the UI can ask "Is this right?".
CREATE OR REPLACE FUNCTION fill_from_profile(p_complaint int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_me int; s student%ROWTYPE; v_hostel text; v_filled int := 0; v_given text;
BEGIN
  SELECT person_id INTO v_me FROM complainant_identity WHERE complaint_id = p_complaint;
  SELECT * INTO s FROM student WHERE person_id = v_me;
  IF s.hostel_unit_id IS NULL THEN RETURN 0; END IF;
  SELECT name INTO v_hostel FROM department WHERE unit_id = s.hostel_unit_id;

  IF EXISTS (SELECT 1 FROM complaint c JOIN category_requirement r USING (category_id)
             WHERE c.complaint_id = p_complaint AND r.field_name = 'hostel') THEN
    INSERT INTO complaint_detail VALUES (p_complaint, 'hostel', v_hostel, 'Profile')
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_filled = ROW_COUNT;

    -- the room is only filled in when the complaint is about their own hostel
    SELECT value INTO v_given FROM complaint_detail
    WHERE complaint_id = p_complaint AND field_name = 'hostel';
    IF regexp_replace(lower(v_given), '[^a-z0-9]', '', 'g')
       LIKE '%' || regexp_replace(lower(v_hostel), '[^a-z0-9]', '', 'g') || '%'
       AND EXISTS (SELECT 1 FROM complaint c JOIN category_requirement r USING (category_id)
                   WHERE c.complaint_id = p_complaint AND r.field_name = 'room_or_floor') THEN
      INSERT INTO complaint_detail VALUES (p_complaint, 'room_or_floor', 'Room ' || s.room_no, 'Profile')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  RETURN v_filled;
END $$;

-- =====================================================================
-- C. COMPLETENESS CHECK AND CLARIFICATIONS
-- =====================================================================

-- Mandatory details (per CategoryRequirement) that the complaint is missing.
-- This is the "is the complaint complete?" check, as a single SQL query.
CREATE OR REPLACE FUNCTION check_completeness(p_complaint int)
RETURNS TABLE (field_name varchar, question_prompt varchar)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  SELECT r.field_name, r.question_prompt
  FROM complaint c
  JOIN category_requirement r ON r.category_id = c.category_id
  WHERE c.complaint_id = p_complaint
    AND r.is_mandatory
    AND NOT EXISTS (SELECT 1 FROM complaint_detail d
                    WHERE d.complaint_id = c.complaint_id
                      AND d.field_name = r.field_name)
  ORDER BY r.field_name;
$$;

-- Ask the stored question for every missing mandatory detail
-- (skipping questions that are already open). Returns how many are open.
CREATE OR REPLACE FUNCTION ask_missing_questions(p_complaint int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE v_open int;
BEGIN
  INSERT INTO clarification (complaint_id, field_name, question, asked_by)
  SELECT p_complaint, m.field_name, m.question_prompt, 'AI'
  FROM check_completeness(p_complaint) m
  WHERE NOT EXISTS (SELECT 1 FROM clarification q
                    WHERE q.complaint_id = p_complaint
                      AND q.field_name = m.field_name AND q.answer IS NULL);
  SELECT count(*) INTO v_open FROM clarification
  WHERE complaint_id = p_complaint AND answer IS NULL;
  RETURN v_open;
END $$;

-- Move a complaint forward as far as it can go:
--   no category       -> stays Filed (waits for the triage officer)
--   details missing   -> NeedsInfo with follow-up questions
--   complete          -> Triaged -> routed (Assigned)
CREATE OR REPLACE FUNCTION process_complaint(p_complaint int)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  c complaint%ROWTYPE;
BEGIN
  SELECT * INTO c FROM complaint WHERE complaint_id = p_complaint;
  IF c.status NOT IN ('Filed','Triaged','NeedsInfo') THEN
    RETURN c.status;                          -- already routed
  END IF;
  IF c.category_id IS NULL THEN
    RETURN 'AwaitingTriage';
  END IF;

  PERFORM apply_context(p_complaint);
  PERFORM fill_from_profile(p_complaint);

  IF ask_missing_questions(p_complaint) > 0 THEN
    IF c.status <> 'NeedsInfo' THEN
      PERFORM set_config('app.status_note', 'Waiting for missing details', true);
      UPDATE complaint SET status = 'NeedsInfo' WHERE complaint_id = p_complaint;
    END IF;
    RETURN 'NeedsInfo';
  END IF;

  PERFORM set_config('app.status_note', 'All required details present', true);
  UPDATE complaint SET status = 'Triaged' WHERE complaint_id = p_complaint;
  PERFORM route_complaint(p_complaint);
  RETURN 'Assigned';
END $$;

-- The complainant answers a follow-up question.
CREATE OR REPLACE FUNCTION answer_clarification(p_complaint int, p_seq int, p_answer text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  q clarification%ROWTYPE;
  v_prev text;
BEGIN
  IF NOT is_complainant(p_complaint) THEN
    RAISE EXCEPTION 'Only the complainant can answer questions on complaint %', p_complaint;
  END IF;
  UPDATE clarification SET answer = p_answer, answered_at = app_now()
  WHERE complaint_id = p_complaint AND seq_no = p_seq AND answer IS NULL
  RETURNING * INTO q;
  IF NOT FOUND THEN RAISE EXCEPTION 'No open question % on complaint %', p_seq, p_complaint; END IF;

  IF q.field_name IS NOT NULL THEN
    INSERT INTO complaint_detail (complaint_id, field_name, value, source)
    VALUES (p_complaint, q.field_name, left(p_answer, 200), 'User')
    ON CONFLICT (complaint_id, field_name) DO UPDATE SET value = EXCLUDED.value, source = 'User';
  END IF;

  -- still waiting on other questions?
  IF EXISTS (SELECT 1 FROM clarification WHERE complaint_id = p_complaint AND answer IS NULL) THEN
    RETURN 'NeedsInfo';
  END IF;

  -- status before it went to NeedsInfo
  SELECT old_status INTO v_prev FROM status_history
  WHERE complaint_id = p_complaint AND new_status = 'NeedsInfo'
  ORDER BY seq_no DESC LIMIT 1;

  IF v_prev IN ('Assigned','InProgress','Escalated') THEN
    PERFORM set_config('app.status_note', 'Complainant replied', true);
    UPDATE complaint SET status = v_prev WHERE complaint_id = p_complaint;
    RETURN v_prev;
  END IF;
  RETURN process_complaint(p_complaint);
END $$;

-- People the complainant might mean (e.g. "Ram"), best match first.
-- Connections to the complainant rank highest: teaches one of their
-- courses > same department > same hostel > anyone else.
CREATE OR REPLACE FUNCTION find_person_candidates(p_name text, p_stated_role text DEFAULT 'Unknown')
RETURNS TABLE (person_id int, full_name text, person_type varchar, department varchar,
               connection text, score int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = sunwai, public AS $$
  WITH me AS (SELECT p.person_id, p.unit_id, s.hostel_unit_id
              FROM person p LEFT JOIN student s USING (person_id)
              WHERE p.person_id = current_person_id())
  SELECT p.person_id, person_name(p.person_id), p.person_type, d.name,
         CASE
           WHEN teach.title IS NOT NULL THEN 'Teaches your course ' || teach.title
           WHEN p.unit_id = me.unit_id THEN 'Same department as you'
           WHEN s.hostel_unit_id = me.hostel_unit_id THEN 'Lives in your hostel'
           ELSE 'Other'
         END,
         CASE WHEN teach.title IS NOT NULL THEN 3
              WHEN p.unit_id = me.unit_id OR s.hostel_unit_id = me.hostel_unit_id THEN 2
              ELSE 1 END
  FROM person p
  JOIN department d ON d.unit_id = p.unit_id
  LEFT JOIN student s ON s.person_id = p.person_id
  CROSS JOIN me
  LEFT JOIN LATERAL (
      SELECT co.title FROM course_offering o
      JOIN course co USING (course_code)
      JOIN enrollment e ON e.offering_id = o.offering_id
      WHERE o.faculty_id = p.person_id AND e.student_id = me.person_id
      LIMIT 1) teach ON TRUE
  WHERE p.person_id <> me.person_id
    AND (p.first_name || ' ' || p.last_name) ILIKE '%' || p_name || '%'
    AND (p_stated_role = 'Unknown' OR p.person_type = p_stated_role)
  ORDER BY 6 DESC, 2
  LIMIT 5;
$$;

-- =====================================================================
-- D. ROUTING WITH THE CONFLICT-OF-INTEREST CHECK
-- =====================================================================

-- Assign to a committee. Members with a conflict are recused (logged in
-- ConflictExclusion); if too few remain for quorum the case goes to the
-- Ombudsperson instead.
CREATE OR REPLACE FUNCTION assign_to_committee(p_complaint int, p_committee int, p_rule int,
                                               p_type text, p_prefix text, p_due timestamptz)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_comm      committee%ROWTYPE;
  v_target    int := p_committee;
  v_decision  int;
  v_total     int;
  v_recused   int;
  v_list      text;
  v_note      text;
BEGIN
  SELECT * INTO v_comm FROM committee WHERE committee_id = p_committee;

  CREATE TEMP TABLE IF NOT EXISTS tmp_recusal (person_id int, reason text) ON COMMIT DROP;
  DELETE FROM tmp_recusal;
  INSERT INTO tmp_recusal
  SELECT m.person_id, conflict_reason(m.person_id, p_complaint, TRUE)
  FROM committee_member m
  WHERE m.committee_id = p_committee
    AND m.term_start <= app_now()::date
    AND (m.term_end IS NULL OR m.term_end >= app_now()::date);

  SELECT count(*), count(reason) INTO v_total, v_recused FROM tmp_recusal;
  SELECT string_agg(person_name(person_id) || ' (' || conflict_label(reason) || ')', '; ')
    INTO v_list FROM tmp_recusal WHERE reason IS NOT NULL;

  v_note := p_prefix || format('Assigned to %s: %s of %s members eligible (quorum %s).',
                               v_comm.name, v_total - v_recused, v_total, v_comm.quorum);
  IF v_list IS NOT NULL THEN v_note := v_note || ' Recused: ' || v_list || '.'; END IF;

  IF v_total - v_recused < v_comm.quorum THEN
    SELECT committee_id INTO v_target FROM committee WHERE committee_type = 'Ombudsperson';
    v_note := v_note || ' Quorum not met, so referred to the Ombudsperson.';
  END IF;

  INSERT INTO routing_decision (complaint_id, rule_id, assigned_committee_id, decision_type,
                                reason, decided_at, due_at)
  VALUES (p_complaint, p_rule, v_target, p_type, left(v_note, 300), app_now(), p_due)
  RETURNING decision_id INTO v_decision;

  INSERT INTO conflict_exclusion (decision_id, person_id, reason_code)
  SELECT v_decision, person_id, reason FROM tmp_recusal WHERE reason IS NOT NULL;
  RETURN v_decision;
END $$;

-- Assign to the holder of a post. If that person has a conflict, walk UP the
-- reporting hierarchy until an eligible holder is found. Every skipped
-- person is logged in ConflictExclusion with the reason.
CREATE OR REPLACE FUNCTION assign_up_chain(p_complaint int, p_start_position int, p_rule int,
                                           p_type text, p_prefix text, p_due timestamptz)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_pos      int := p_start_position;
  v_holder   int;
  v_title    text;
  v_reason   text;
  v_skipped  jsonb := '[]'::jsonb;
  v_list     text;
  v_note     text;
  v_decision int;
BEGIN
  LOOP
    IF v_pos IS NULL THEN
      -- nobody eligible left in the chain: the SGRC takes the case
      RETURN assign_to_committee(p_complaint,
               (SELECT committee_id FROM committee WHERE committee_type = 'SGRC'),
               p_rule, p_type, p_prefix || 'No eligible office holder in the chain. ', p_due);
    END IF;
    SELECT holder_id, title INTO v_holder, v_title FROM position WHERE position_id = v_pos;
    v_reason := conflict_reason(v_holder, p_complaint);
    EXIT WHEN v_reason IS NULL;
    v_skipped := v_skipped || jsonb_build_object('person', v_holder, 'reason', v_reason,
                                                 'title', v_title);
    SELECT reports_to INTO v_pos FROM position WHERE position_id = v_pos;
  END LOOP;

  v_note := p_prefix || format('Assigned to %s (%s).', v_title, person_name(v_holder));
  SELECT string_agg(format('%s - %s %s', e->>'title', person_name((e->>'person')::int),
                           conflict_label(e->>'reason')), '; ')
    INTO v_list FROM jsonb_array_elements(v_skipped) e;
  IF v_list IS NOT NULL THEN v_note := v_note || ' Skipped: ' || v_list || '.'; END IF;

  INSERT INTO routing_decision (complaint_id, rule_id, assigned_person_id, decision_type,
                                reason, decided_at, due_at)
  VALUES (p_complaint, p_rule, v_holder, p_type, left(v_note, 300), app_now(), p_due)
  RETURNING decision_id INTO v_decision;

  INSERT INTO conflict_exclusion (decision_id, person_id, reason_code)
  SELECT DISTINCT ON ((e->>'person')::int) v_decision, (e->>'person')::int, e->>'reason'
  FROM jsonb_array_elements(v_skipped) e;
  RETURN v_decision;
END $$;

-- Route a complete, categorised complaint to its first handler.
CREATE OR REPLACE FUNCTION route_complaint(p_complaint int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  c          complaint%ROWTYPE;
  v_cat      category%ROWTYPE;
  v_rule     routing_rule%ROWTYPE;
  v_ai       text;
  v_priority text;
  v_due      timestamptz;
  v_prefix   text;
  v_pos      int;
  v_decision int;
BEGIN
  SELECT * INTO c FROM complaint WHERE complaint_id = p_complaint FOR UPDATE;
  IF c.category_id IS NULL THEN
    RAISE EXCEPTION 'Complaint % has no category yet', p_complaint;
  END IF;
  IF EXISTS (SELECT 1 FROM check_completeness(p_complaint)) THEN
    RAISE EXCEPTION 'Complaint % is missing required details: %', p_complaint,
      (SELECT string_agg(field_name, ', ') FROM check_completeness(p_complaint));
  END IF;
  IF c.status <> 'Triaged' THEN
    RAISE EXCEPTION 'Complaint % must be Triaged before routing (it is %)', p_complaint, c.status;
  END IF;

  SELECT * INTO v_cat  FROM category WHERE category_id = c.category_id;
  SELECT * INTO v_rule FROM routing_rule WHERE category_id = c.category_id
  ORDER BY priority LIMIT 1;
  SELECT urgency INTO v_ai FROM ai_triage_result WHERE complaint_id = p_complaint;

  -- priority = max(category base, urgency); a triage officer's priority
  -- (already stored on the complaint) takes the place of the AI's.
  v_priority := compute_priority(v_cat.base_priority, coalesce(c.priority, v_ai));
  v_due := app_now() + make_interval(hours => coalesce(v_cat.sla_hours, default_sla_hours(v_priority)));
  v_prefix := format('Rule "%s" -> %s. Priority %s. ', v_cat.name,
                     coalesce(v_rule.target_role_code,
                              (SELECT name FROM committee WHERE committee_id = v_rule.target_committee_id)),
                     v_priority);

  IF v_rule.target_committee_id IS NOT NULL THEN
    v_decision := assign_to_committee(p_complaint, v_rule.target_committee_id, v_rule.rule_id,
                                      'Initial', v_prefix, v_due);
  ELSE
    v_pos := resolve_role_position(v_rule.target_role_code, c.unit_id);
    IF v_pos IS NULL THEN
      RAISE EXCEPTION 'No post with role % exists for unit %', v_rule.target_role_code, c.unit_id;
    END IF;
    v_decision := assign_up_chain(p_complaint, v_pos, v_rule.rule_id, 'Initial', v_prefix, v_due);
  END IF;

  PERFORM set_config('app.status_note',
                     (SELECT reason FROM routing_decision WHERE decision_id = v_decision), true);
  UPDATE complaint SET priority = v_priority, status = 'Assigned' WHERE complaint_id = p_complaint;
  PERFORM set_config('app.status_note', '', true);
  RETURN v_decision;
END $$;

-- Triage officer confirms or corrects the category (and optionally the
-- priority), then the complaint continues automatically.
CREATE OR REPLACE FUNCTION confirm_triage(p_complaint int, p_category int,
                                          p_priority text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
BEGIN
  IF NOT is_triage_officer() THEN
    RAISE EXCEPTION 'Only the triage officer can confirm triage';
  END IF;
  UPDATE complaint SET category_id = p_category,
                       priority = coalesce(p_priority, priority)
  WHERE complaint_id = p_complaint AND status IN ('Filed','Triaged','NeedsInfo');
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint % is not waiting for triage', p_complaint; END IF;
  UPDATE ai_triage_result SET reviewed_by = current_person_id(), reviewed_at = app_now()
  WHERE complaint_id = p_complaint;
  RETURN process_complaint(p_complaint);
END $$;

-- =====================================================================
-- E. ESCALATION AND STALE INFORMATION REQUESTS
-- =====================================================================

-- Escalate every complaint whose deadline has passed to the next post up
-- the reporting chain (conflict check runs again). For academic and exam
-- complaints, the step after the Dean Academics is the SGRC.
-- Run by the backend's scheduler every few minutes. Returns the count.
CREATE OR REPLACE FUNCTION escalate_overdue()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  r          record;
  v_cur      position%ROWTYPE;
  v_next     int;
  v_domain   text;
  v_hours    int;
  v_prefix   text;
  v_count    int := 0;
BEGIN
  FOR r IN
    SELECT c.complaint_id, c.unit_id, c.status, c.priority, c.category_id,
           d.assigned_person_id, d.due_at, d.rule_id
    FROM complaint c
    JOIN routing_decision d ON d.decision_id = latest_decision(c.complaint_id)
    WHERE c.status IN ('Assigned','InProgress','Escalated')
      AND d.assigned_person_id IS NOT NULL
      AND d.due_at < app_now()
  LOOP
    -- the post the current handler holds for this complaint
    SELECT pos.* INTO v_cur
    FROM position pos
    LEFT JOIN unit_ancestors(r.unit_id) a ON a.unit_id = pos.unit_id
    WHERE pos.holder_id = r.assigned_person_id
    ORDER BY (a.depth IS NULL), a.depth, pos.position_id
    LIMIT 1;

    SELECT domain, coalesce(sla_hours, default_sla_hours(r.priority))
      INTO v_domain, v_hours FROM category WHERE category_id = r.category_id;
    v_prefix := format('Deadline missed (was due %s). Escalated from %s. ',
                       to_char(r.due_at, 'DD Mon HH24:MI'), coalesce(v_cur.title, 'handler'));

    IF v_cur.role_code = 'DeanAcademics' AND v_domain IN ('Academic','Exam') THEN
      PERFORM assign_to_committee(r.complaint_id,
                (SELECT committee_id FROM committee WHERE committee_type = 'SGRC'),
                r.rule_id, 'Escalation', v_prefix, app_now() + make_interval(hours => v_hours));
    ELSE
      v_next := v_cur.reports_to;
      CONTINUE WHEN v_next IS NULL;              -- already at the top
      PERFORM assign_up_chain(r.complaint_id, v_next, r.rule_id, 'Escalation', v_prefix,
                              app_now() + make_interval(hours => v_hours));
    END IF;

    IF r.status <> 'Escalated' THEN
      PERFORM set_config('app.status_note', 'Deadline missed', true);
      UPDATE complaint SET status = 'Escalated' WHERE complaint_id = r.complaint_id;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  PERFORM set_config('app.status_note', '', true);
  RETURN v_count;
END $$;

-- Close complaints that have waited more than p_days for the complainant.
CREATE OR REPLACE FUNCTION close_stale_needs_info(p_days int DEFAULT 7)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE v_count int;
BEGIN
  PERFORM set_config('app.status_note', 'No reply from complainant within ' || p_days || ' days', true);
  UPDATE complaint c
     SET status = 'Closed', resolution_outcome = 'InsufficientInfo'
   WHERE c.status = 'NeedsInfo'
     AND (SELECT max(changed_at) FROM status_history h
          WHERE h.complaint_id = c.complaint_id AND h.new_status = 'NeedsInfo')
         < app_now() - make_interval(days => p_days);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM set_config('app.status_note', '', true);
  RETURN v_count;
END $$;

-- =====================================================================
-- F. HANDLER ACTIONS
-- =====================================================================

-- A handler (or committee member) asks the complainant for information.
-- The deadline pauses while the complaint waits (trigger T4).
CREATE OR REPLACE FUNCTION request_info(p_complaint int, p_question text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE v_seq int;
BEGIN
  IF NOT (is_current_handler(p_complaint) OR is_committee_handler(p_complaint)) THEN
    RAISE EXCEPTION 'Only the current handler can request information on complaint %', p_complaint;
  END IF;
  INSERT INTO clarification (complaint_id, field_name, question, asked_by)
  VALUES (p_complaint, NULL, p_question, 'Handler')
  RETURNING seq_no INTO v_seq;
  PERFORM set_config('app.status_note', 'Handler asked: ' || left(p_question, 150), true);
  UPDATE complaint SET status = 'NeedsInfo' WHERE complaint_id = p_complaint;
  PERFORM set_config('app.status_note', '', true);
  RETURN v_seq;
END $$;

-- Record that a complaint was opened (confidential / sensitive cases are logged).
CREATE OR REPLACE FUNCTION open_complaint(p_complaint int)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
BEGIN
  IF NOT can_see_complaint(p_complaint) THEN
    RAISE EXCEPTION 'permission denied for complaint %', p_complaint
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF is_sensitive(p_complaint)
     OR (SELECT visibility <> 'Public' FROM complaint WHERE complaint_id = p_complaint) THEN
    INSERT INTO access_log (complaint_id, accessed_by, db_role, action, accessed_at)
    VALUES (p_complaint, current_person_id(),
            coalesce(nullif(current_setting('app.role', true), ''), session_user), 'View', app_now());
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END $$;

-- =====================================================================
-- G. COMPLAINANT ACTIONS: RATE, REOPEN, APPEAL
-- =====================================================================

CREATE OR REPLACE FUNCTION rate_and_close(p_complaint int, p_rating int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
BEGIN
  IF NOT is_complainant(p_complaint) THEN
    RAISE EXCEPTION 'Only the complainant can rate complaint %', p_complaint;
  END IF;
  PERFORM set_config('app.status_note', 'Rated ' || p_rating || '/5 by complainant', true);
  UPDATE complaint SET feedback_rating = p_rating, status = 'Closed'
  WHERE complaint_id = p_complaint AND status = 'Resolved';
  IF NOT FOUND THEN RAISE EXCEPTION 'Complaint % is not resolved', p_complaint; END IF;
  PERFORM set_config('app.status_note', '', true);
END $$;

-- Reopen a resolved complaint (once, within 7 days). Creates a new
-- complaint linked to the original (recursive relationship Reopens) and
-- routes it straight away.
CREATE OR REPLACE FUNCTION reopen_complaint(p_complaint int, p_reason text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  c     complaint%ROWTYPE;
  v_new int;
BEGIN
  IF NOT is_complainant(p_complaint) THEN
    RAISE EXCEPTION 'Only the complainant can reopen complaint %', p_complaint;
  END IF;
  SELECT * INTO c FROM complaint WHERE complaint_id = p_complaint;
  IF c.status NOT IN ('Resolved','Closed') OR c.resolved_at IS NULL THEN
    RAISE EXCEPTION 'Only a resolved complaint can be reopened';
  END IF;
  IF c.resolved_at < app_now() - interval '7 days' THEN
    RAISE EXCEPTION 'The 7-day reopen window has passed';
  END IF;
  IF c.reopened_from IS NOT NULL
     OR EXISTS (SELECT 1 FROM complaint WHERE reopened_from = p_complaint) THEN
    RAISE EXCEPTION 'A complaint can only be reopened once';
  END IF;

  INSERT INTO complaint (description, visibility, filed_at, category_id, unit_id,
                         location_text, offering_id, script_id, reopened_from, priority)
  VALUES ('Reopened: ' || p_reason || E'\n\nOriginal complaint: ' || c.description,
          c.visibility, app_now(), c.category_id, c.unit_id, c.location_text,
          c.offering_id, c.script_id, p_complaint, c.priority)
  RETURNING complaint_id INTO v_new;

  INSERT INTO complainant_identity
  SELECT v_new, person_id, contact_consent FROM complainant_identity WHERE complaint_id = p_complaint;
  INSERT INTO complaint_party (complaint_id, party_no, person_id, party_role, stated_role, description)
  SELECT v_new, party_no, person_id, party_role, stated_role, description
  FROM complaint_party WHERE complaint_id = p_complaint;
  INSERT INTO complaint_detail
  SELECT v_new, field_name, value, source FROM complaint_detail WHERE complaint_id = p_complaint;

  IF c.status = 'Resolved' THEN
    PERFORM set_config('app.status_note', 'Reopened as complaint #' || v_new, true);
    UPDATE complaint SET status = 'Closed' WHERE complaint_id = p_complaint;
  END IF;
  PERFORM process_complaint(v_new);
  RETURN v_new;
END $$;

-- Appeal a decision to the Ombudsperson within the category's appeal window.
CREATE OR REPLACE FUNCTION file_appeal(p_complaint int, p_grounds text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  c        complaint%ROWTYPE;
  v_window int;
  v_judge  int;
  v_id     int;
BEGIN
  IF NOT is_complainant(p_complaint) THEN
    RAISE EXCEPTION 'Only the complainant can appeal complaint %', p_complaint;
  END IF;
  SELECT * INTO c FROM complaint WHERE complaint_id = p_complaint;
  IF c.status NOT IN ('Resolved','Rejected') THEN
    RAISE EXCEPTION 'Only a resolved or rejected complaint can be appealed (it is %)', c.status;
  END IF;
  SELECT appeal_window_days INTO v_window FROM category WHERE category_id = c.category_id;
  IF c.resolved_at < app_now() - make_interval(days => v_window) THEN
    RAISE EXCEPTION 'The % day appeal window has passed', v_window;
  END IF;

  SELECT m.person_id INTO v_judge
  FROM committee_member m JOIN committee co USING (committee_id)
  WHERE co.committee_type = 'Ombudsperson'
  ORDER BY (m.member_role = 'Chair') DESC LIMIT 1;

  INSERT INTO appeal (complaint_id, appellant_id, heard_by, filed_on, grounds)
  VALUES (p_complaint, current_person_id(), v_judge, app_now()::date, p_grounds)
  RETURNING appeal_id INTO v_id;

  PERFORM set_config('app.status_note', 'Appeal #' || v_id || ' filed with the Ombudsperson', true);
  UPDATE complaint SET status = 'Appealed' WHERE complaint_id = p_complaint;
  PERFORM set_config('app.status_note', '', true);
  RETURN v_id;
END $$;

-- The Ombudsperson decides an appeal.
--   Dismissed -> the complaint is closed.
--   Upheld    -> the complaint goes back to its handler (InProgress).
CREATE OR REPLACE FUNCTION decide_appeal(p_appeal int, p_status text, p_outcome text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE v_complaint int;
BEGIN
  IF NOT is_ombudsperson() THEN RAISE EXCEPTION 'Only the Ombudsperson can decide appeals'; END IF;
  IF p_status NOT IN ('Upheld','Dismissed') THEN RAISE EXCEPTION 'Decision must be Upheld or Dismissed'; END IF;
  UPDATE appeal SET status = p_status, outcome = p_outcome
  WHERE appeal_id = p_appeal AND status = 'Pending'
  RETURNING complaint_id INTO v_complaint;
  IF v_complaint IS NULL THEN RAISE EXCEPTION 'Appeal % is not pending', p_appeal; END IF;

  PERFORM set_config('app.status_note', 'Appeal ' || lower(p_status) || ': ' || left(p_outcome, 150), true);
  UPDATE complaint SET status = CASE p_status WHEN 'Upheld' THEN 'InProgress' ELSE 'Closed' END
  WHERE complaint_id = v_complaint;
  PERFORM set_config('app.status_note', '', true);
END $$;

-- =====================================================================
-- H. RE-EVALUATION (exam module)
-- =====================================================================

-- Choose an independent reviewer from the course's department: never the
-- original evaluator, never anyone with a conflict, fewest open reviews first.
CREATE OR REPLACE FUNCTION assign_reviewer(p_complaint int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_dept      int;
  v_evaluator int;
  v_reviewer  int;
  v_due       timestamptz;
  v_decision  int;
BEGIN
  SELECT co.unit_id, s.evaluator_id INTO v_dept, v_evaluator
  FROM complaint c
  JOIN answer_script s ON s.script_id = c.script_id
  JOIN exam e ON e.exam_id = s.exam_id
  JOIN course_offering o ON o.offering_id = e.offering_id
  JOIN course co ON co.course_code = o.course_code
  WHERE c.complaint_id = p_complaint;
  IF v_dept IS NULL THEN RAISE EXCEPTION 'Complaint % is not a re-evaluation request', p_complaint; END IF;

  SELECT f.person_id INTO v_reviewer
  FROM faculty f JOIN person p USING (person_id)
  WHERE p.unit_id = v_dept
    AND conflict_reason(f.person_id, p_complaint) IS NULL
  ORDER BY (SELECT count(*) FROM routing_decision d JOIN complaint c2 USING (complaint_id)
            WHERE d.assigned_person_id = f.person_id AND c2.script_id IS NOT NULL
              AND c2.status NOT IN ('Resolved','Closed','Rejected')),
           f.person_id
  LIMIT 1;
  IF v_reviewer IS NULL THEN RAISE EXCEPTION 'No independent reviewer available'; END IF;

  SELECT due_at INTO v_due FROM routing_decision WHERE decision_id = latest_decision(p_complaint);

  INSERT INTO routing_decision (complaint_id, rule_id, assigned_person_id, decision_type,
                                reason, decided_at, due_at)
  VALUES (p_complaint, (SELECT rule_id FROM routing_rule WHERE category_id = 9 LIMIT 1),
          v_reviewer, 'Reroute',
          format('Controller of Examinations assigned independent reviewer %s. Original evaluator %s excluded.',
                 person_name(v_reviewer), person_name(v_evaluator)),
          app_now(), v_due)
  RETURNING decision_id INTO v_decision;

  INSERT INTO conflict_exclusion VALUES (v_decision, v_evaluator, 'OriginalEvaluator');
  RETURN v_decision;
END $$;

-- A student requests re-evaluation of specific questions.
--   p_disputes : [{"question_no":3,"marks_awarded":4,"marks_claimed":7,"reason":"..."}]
-- Creates a complaint (category "Exam - Re-evaluation"), routes it to the
-- Controller of Examinations, who assigns an independent reviewer.
CREATE OR REPLACE FUNCTION file_reevaluation(p_script int, p_disputes jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  s       answer_script%ROWTYPE;
  v_exam  exam%ROWTYPE;
  v_title text;
  v_id    int;
  d       jsonb;
BEGIN
  SELECT * INTO s FROM answer_script WHERE script_id = p_script;
  IF s.student_id IS DISTINCT FROM current_person_id() THEN
    RAISE EXCEPTION 'You can only request re-evaluation of your own answer script';
  END IF;
  IF jsonb_array_length(p_disputes) = 0 THEN RAISE EXCEPTION 'List at least one question'; END IF;
  SELECT * INTO v_exam FROM exam WHERE exam_id = s.exam_id;
  SELECT co.course_code || ' ' || co.title INTO v_title
  FROM course_offering o JOIN course co USING (course_code) WHERE o.offering_id = v_exam.offering_id;

  v_id := file_complaint(format('Re-evaluation request for %s (%s exam), questions %s.',
                                v_title, v_exam.exam_type,
                                (SELECT string_agg(x->>'question_no', ', ')
                                 FROM jsonb_array_elements(p_disputes) x)),
                         'Confidential', TRUE);
  UPDATE complaint SET category_id = 9, script_id = p_script, offering_id = v_exam.offering_id
  WHERE complaint_id = v_id;

  INSERT INTO complaint_detail VALUES
    (v_id, 'course', v_title, 'User'),
    (v_id, 'exam', v_exam.exam_type, 'User'),
    (v_id, 'question_numbers',
     (SELECT string_agg(x->>'question_no', ', ') FROM jsonb_array_elements(p_disputes) x), 'User');

  FOR d IN SELECT * FROM jsonb_array_elements(p_disputes) LOOP
    INSERT INTO question_dispute (complaint_id, question_no, marks_awarded, marks_claimed, student_reason)
    VALUES (v_id, (d->>'question_no')::int, (d->>'marks_awarded')::numeric,
            (d->>'marks_claimed')::numeric, d->>'reason');
  END LOOP;

  PERFORM process_complaint(v_id);   -- routes to the Controller of Examinations
  PERFORM assign_reviewer(v_id);     -- CoE hands it to an independent reviewer
  RETURN v_id;
END $$;

-- The reviewer decides one disputed question. When every question is
-- decided the re-evaluation is resolved automatically.
CREATE OR REPLACE FUNCTION decide_dispute(p_complaint int, p_question int,
                                          p_decision text, p_revised numeric)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE v_status text;
BEGIN
  IF NOT is_current_handler(p_complaint) THEN
    RAISE EXCEPTION 'Only the assigned reviewer can decide disputes on complaint %', p_complaint;
  END IF;
  UPDATE question_dispute
     SET reviewer_decision = p_decision,
         revised_marks = CASE WHEN p_decision = 'Rejected' THEN marks_awarded ELSE p_revised END
   WHERE complaint_id = p_complaint AND question_no = p_question;
  IF NOT FOUND THEN RAISE EXCEPTION 'Question % is not disputed on complaint %', p_question, p_complaint; END IF;

  SELECT status INTO v_status FROM complaint WHERE complaint_id = p_complaint;
  IF v_status IN ('Assigned','Escalated') THEN
    UPDATE complaint SET status = 'InProgress' WHERE complaint_id = p_complaint;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM question_dispute
                 WHERE complaint_id = p_complaint AND reviewer_decision IS NULL) THEN
    PERFORM set_config('app.status_note', 'All disputed questions reviewed', true);
    UPDATE complaint
       SET status = 'Resolved',
           resolution_outcome = CASE WHEN EXISTS (
                 SELECT 1 FROM question_dispute WHERE complaint_id = p_complaint
                   AND reviewer_decision IN ('Accepted','Partial')) THEN 'Upheld' ELSE 'Dismissed' END,
           resolution_note = (SELECT string_agg(format('Q%s: %s (%s -> %s)', question_no,
                                     reviewer_decision, marks_awarded, revised_marks), '; '
                                     ORDER BY question_no)
                              FROM question_dispute WHERE complaint_id = p_complaint)
     WHERE complaint_id = p_complaint;
    PERFORM set_config('app.status_note', '', true);
    RETURN 'Resolved';
  END IF;
  RETURN 'InProgress';
END $$;
