-- =====================================================================
--  04_triggers.sql : rules the database enforces on every change,
--  no matter which program (or person) makes the change.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- T1. Visibility rules on Complaint
--   * A Sensitive category can never be Public -> forced to Confidential.
--   * Anonymous is only allowed if the category allows it.
--   * resolved_at is stamped automatically when a complaint is resolved.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_complaint_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_cat category%ROWTYPE;
BEGIN
  IF NEW.category_id IS NOT NULL THEN
    SELECT * INTO v_cat FROM category WHERE category_id = NEW.category_id;
    IF v_cat.sensitivity = 'Sensitive' AND NEW.visibility = 'Public' THEN
      NEW.visibility := 'Confidential';
    END IF;
    IF NEW.visibility = 'Anonymous' AND NOT v_cat.anonymous_allowed THEN
      RAISE EXCEPTION 'Category "%" does not allow anonymous complaints', v_cat.name;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('Resolved','Rejected') THEN
    NEW.resolved_at := app_now();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER complaint_rules
BEFORE INSERT OR UPDATE ON complaint
FOR EACH ROW EXECUTE FUNCTION trg_complaint_rules();

-- ---------------------------------------------------------------------
-- T2. Status workflow (state machine).
-- Only these transitions are allowed; anything else is rejected.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION allowed_transition(p_from text, p_to text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_from, p_to) IN (
    ('Filed','Triaged'),      ('Filed','NeedsInfo'),
    ('Triaged','Assigned'),   ('Triaged','NeedsInfo'),
    ('NeedsInfo','Triaged'),  ('NeedsInfo','Assigned'),  ('NeedsInfo','InProgress'),
    ('NeedsInfo','Escalated'),('NeedsInfo','Closed'),
    ('Assigned','InProgress'),('Assigned','NeedsInfo'),  ('Assigned','Escalated'),
    ('Assigned','Rejected'),
    ('InProgress','Resolved'),('InProgress','NeedsInfo'),('InProgress','Escalated'),
    ('InProgress','Rejected'),
    ('Escalated','InProgress'),('Escalated','NeedsInfo'),('Escalated','Rejected'),
    ('Escalated','Resolved'),
    ('Resolved','Closed'),    ('Resolved','Appealed'),
    ('Rejected','Closed'),    ('Rejected','Appealed'),
    ('Appealed','Closed'),    ('Appealed','InProgress')
  );
$$;

CREATE OR REPLACE FUNCTION trg_validate_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT allowed_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'Invalid status change: % -> % (complaint %)',
                    OLD.status, NEW.status, OLD.complaint_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER complaint_validate_status
BEFORE UPDATE OF status ON complaint
FOR EACH ROW EXECUTE FUNCTION trg_validate_status();

-- ---------------------------------------------------------------------
-- T3. Automatic status history (weak entity StatusHistory).
-- Every insert / status change writes a history row. The optional note
-- comes from the session setting app.status_note.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_status_history() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO status_history (complaint_id, seq_no, old_status, new_status,
                                changed_by, changed_at, note)
    VALUES (NEW.complaint_id,
            coalesce((SELECT max(seq_no) FROM status_history
                      WHERE complaint_id = NEW.complaint_id), 0) + 1,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END,
            NEW.status,
            current_person_id(),
            app_now(),
            left(nullif(current_setting('app.status_note', true), ''), 200));
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER complaint_status_history
AFTER INSERT OR UPDATE OF status ON complaint
FOR EACH ROW EXECUTE FUNCTION trg_status_history();

-- ---------------------------------------------------------------------
-- T4. Pause the deadline while waiting for the complainant.
-- When a complaint leaves NeedsInfo, the current deadline is pushed back
-- by exactly the time it spent waiting.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_sla_pause() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_waiting_since timestamptz;
BEGIN
  IF OLD.status = 'NeedsInfo' AND NEW.status <> 'NeedsInfo' THEN
    SELECT max(changed_at) INTO v_waiting_since
    FROM status_history
    WHERE complaint_id = NEW.complaint_id AND new_status = 'NeedsInfo';

    UPDATE routing_decision
       SET due_at = due_at + (app_now() - v_waiting_since)
     WHERE decision_id = latest_decision(NEW.complaint_id)
       AND due_at IS NOT NULL;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER complaint_sla_pause
AFTER UPDATE OF status ON complaint
FOR EACH ROW EXECUTE FUNCTION trg_sla_pause();

-- ---------------------------------------------------------------------
-- T5. Never assign a re-evaluation to the original evaluator.
-- (Second line of defence: the routing procedure already skips them.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_block_original_evaluator() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.assigned_person_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM complaint c JOIN answer_script s ON s.script_id = c.script_id
       WHERE c.complaint_id = NEW.complaint_id AND s.evaluator_id = NEW.assigned_person_id)
  THEN
    RAISE EXCEPTION 'The original evaluator cannot review their own script (complaint %)',
                    NEW.complaint_id;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER decision_block_original_evaluator
BEFORE INSERT ON routing_decision
FOR EACH ROW EXECUTE FUNCTION trg_block_original_evaluator();

-- ---------------------------------------------------------------------
-- T6. Log every mark change and update the script total.
-- Fires when a reviewer records revised marks for a disputed question.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_log_mark_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = sunwai, public AS $$
DECLARE
  v_script   int;
  v_old      numeric;
  v_reviewer int;
BEGIN
  IF NEW.revised_marks IS NULL
     OR NEW.revised_marks IS NOT DISTINCT FROM OLD.revised_marks THEN
    RETURN NULL;
  END IF;

  SELECT script_id INTO v_script FROM complaint WHERE complaint_id = NEW.complaint_id;
  v_old := coalesce(OLD.revised_marks, OLD.marks_awarded);
  IF v_old = NEW.revised_marks THEN
    RETURN NULL;                      -- dispute rejected: marks unchanged, nothing to log
  END IF;

  -- reviewer = the logged-in faculty, else the assigned reviewer
  v_reviewer := coalesce(
      (SELECT person_id FROM faculty WHERE person_id = current_person_id()),
      (SELECT assigned_person_id FROM routing_decision
        WHERE decision_id = latest_decision(NEW.complaint_id)));

  INSERT INTO marks_change_log (script_id, complaint_id, question_no, old_marks,
                                new_marks, changed_by, changed_at, reason)
  VALUES (v_script, NEW.complaint_id, NEW.question_no, v_old, NEW.revised_marks,
          v_reviewer, app_now(),
          'Re-evaluation: ' || NEW.reviewer_decision);

  UPDATE answer_script
     SET total_marks = total_marks + (NEW.revised_marks - v_old)
   WHERE script_id = v_script;
  RETURN NULL;
END $$;

CREATE TRIGGER dispute_log_mark_change
AFTER UPDATE OF revised_marks ON question_dispute
FOR EACH ROW EXECUTE FUNCTION trg_log_mark_change();

-- ---------------------------------------------------------------------
-- T7. Append-only audit tables: history can never be edited or deleted.
-- (Enforced here for everyone, and also via REVOKE in 07_security.sql.)
-- RoutingDecision may only have its deadline moved (by the SLA pause).
-- Deleting a whole complaint (ON DELETE CASCADE) is still allowed for
-- the administrator so the demo database can be reset.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN
    RETURN OLD;                       -- cascade from deleting a complaint
  END IF;
  IF TG_TABLE_NAME = 'routing_decision' AND TG_OP = 'UPDATE'
     AND (to_jsonb(NEW) - 'due_at') = (to_jsonb(OLD) - 'due_at') THEN
    RETURN NEW;                       -- only the deadline moved
  END IF;
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP;
END $$;

CREATE TRIGGER status_history_append_only   BEFORE UPDATE OR DELETE ON status_history
FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER routing_decision_append_only BEFORE UPDATE OR DELETE ON routing_decision
FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER conflict_exclusion_append_only BEFORE UPDATE OR DELETE ON conflict_exclusion
FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER access_log_append_only       BEFORE UPDATE OR DELETE ON access_log
FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER marks_change_log_append_only BEFORE UPDATE OR DELETE ON marks_change_log
FOR EACH ROW EXECUTE FUNCTION trg_append_only();

-- ---------------------------------------------------------------------
-- T8. Auto-number the weak entities' partial keys when not supplied
-- (Clarification.seq_no, ComplaintParty.party_no).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_next_clarification_no() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.seq_no IS NULL THEN
    NEW.seq_no := coalesce((SELECT max(seq_no) FROM clarification
                            WHERE complaint_id = NEW.complaint_id), 0) + 1;
  END IF;
  NEW.asked_at := app_now();
  RETURN NEW;
END $$;

CREATE TRIGGER clarification_seq BEFORE INSERT ON clarification
FOR EACH ROW EXECUTE FUNCTION trg_next_clarification_no();

CREATE OR REPLACE FUNCTION trg_next_party_no() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.party_no IS NULL THEN
    NEW.party_no := coalesce((SELECT max(party_no) FROM complaint_party
                              WHERE complaint_id = NEW.complaint_id), 0) + 1;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER complaint_party_no BEFORE INSERT ON complaint_party
FOR EACH ROW EXECUTE FUNCTION trg_next_party_no();
