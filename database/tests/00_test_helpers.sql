-- Shared helpers for the SQL tests. Every test file runs inside
-- BEGIN ... ROLLBACK, so running the tests never changes the database.
SET search_path TO sunwai, public;

-- ok(condition, description): prints PASS, or stops the test with FAIL
CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_what text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS TRUE THEN
    RAISE NOTICE 'PASS  %', p_what;
  ELSE
    RAISE EXCEPTION 'FAIL  %', p_what;
  END IF;
END $$;

-- act_as(person): set the logged-in user for the next statements
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_person int) RETURNS void
LANGUAGE sql AS $$ SELECT set_config('app.user_id', p_person::text, true); $$;

-- file + triage a complaint in one go (as the given person); returns id
CREATE OR REPLACE FUNCTION pg_temp.new_complaint(p_person int, p_text text, p_cat int,
        p_details jsonb DEFAULT '{}', p_parties jsonb DEFAULT '[]',
        p_urgency text DEFAULT 'Low', p_conf numeric DEFAULT 0.9,
        p_sensitive boolean DEFAULT FALSE, p_vis text DEFAULT 'Public')
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_id int;
BEGIN
  PERFORM pg_temp.act_as(p_person);
  v_id := sunwai.file_complaint(p_text, p_vis, TRUE);
  PERFORM sunwai.record_ai_triage(v_id, p_cat, p_urgency, p_conf, p_sensitive,
                                  left(p_text, 60), p_details, p_parties);
  RETURN v_id;
END $$;

-- who the complaint is currently assigned to
CREATE OR REPLACE FUNCTION pg_temp.assignee(p_id int) RETURNS text
LANGUAGE sql AS $$
  SELECT coalesce(sunwai.person_name(d.assigned_person_id), c.name)
  FROM sunwai.routing_decision d LEFT JOIN sunwai.committee c ON c.committee_id = d.assigned_committee_id
  WHERE d.decision_id = sunwai.latest_decision(p_id);
$$;

SET client_min_messages = notice;
