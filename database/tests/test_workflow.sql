-- Status workflow, history, deadline pause, escalation, reopen, appeals.
\echo '--- test_workflow ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE v_id int; v_err text; v_due1 timestamptz; v_due2 timestamptz; v_seq int;
        v_new int; v_appeal int; v_n int;
BEGIN
  v_id := pg_temp.new_complaint(1001, 'tap broken', 1, '{"room_or_floor":"room 214"}');

  -- 1. Invalid jump Assigned -> Resolved is blocked by the trigger
  BEGIN
    UPDATE complaint SET status = 'Resolved' WHERE complaint_id = v_id;
    v_err := NULL;
  EXCEPTION WHEN check_violation THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'Invalid status change: Assigned -> Resolved%',
                     'state machine blocks Assigned -> Resolved (must go through InProgress)');

  -- 2. Every status change is written to StatusHistory automatically
  PERFORM pg_temp.ok((SELECT string_agg(new_status, '>' ORDER BY seq_no) FROM status_history
                      WHERE complaint_id = v_id) = 'Filed>Triaged>Assigned',
                     'status history recorded automatically: Filed > Triaged > Assigned');

  -- 3. History is append-only (trigger, even for the database owner)
  BEGIN
    UPDATE status_history SET new_status = 'Resolved' WHERE complaint_id = v_id;
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'status_history is append-only%', 'status history cannot be edited');
  BEGIN
    DELETE FROM routing_decision WHERE complaint_id = v_id;
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'routing_decision is append-only%', 'routing decisions cannot be deleted');

  -- 4. Deadline pauses while waiting for the complainant
  SELECT due_at INTO v_due1 FROM routing_decision WHERE decision_id = latest_decision(v_id);
  PERFORM set_config('app.now', (now() + interval '1 hour')::text, true);
  PERFORM pg_temp.act_as(203);                                   -- BH-3 caretaker
  v_seq := request_info(v_id, 'Which tap exactly?');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'NeedsInfo',
                     'handler request_info() puts the complaint in NeedsInfo');
  PERFORM set_config('app.now', (now() + interval '6 hours')::text, true);   -- 5 hours later
  PERFORM pg_temp.act_as(1001);
  PERFORM answer_clarification(v_id, v_seq, 'The one near the window');
  SELECT due_at INTO v_due2 FROM routing_decision WHERE decision_id = latest_decision(v_id);
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Assigned'
                     AND v_due2 - v_due1 = interval '5 hours',
                     'after the reply the complaint returns to its handler and the deadline moved by the 5 hours waited');

  -- 5. Escalation: deadline missed -> next post up the chain (Warden BH-3)
  PERFORM set_config('app.now', (v_due2 + interval '1 hour')::text, true);
  v_n := escalate_overdue();
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Sneha Bhatt'
                     AND (SELECT status FROM complaint WHERE complaint_id = v_id) = 'Escalated'
                     AND (SELECT decision_type FROM routing_decision WHERE decision_id = latest_decision(v_id)) = 'Escalation',
                     'overdue complaint escalated from the BH-3 caretaker to the BH-3 warden');
  -- and again one level up
  PERFORM set_config('app.now', (v_due2 + interval '30 hours')::text, true);
  PERFORM escalate_overdue();
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Nandini Rao',
                     'second escalation reaches the Chief Warden');

  -- 6. Academic complaint: after the Dean Academics the next step is the SGRC
  PERFORM set_config('app.now', '', true);
  v_id := pg_temp.new_complaint(1006, 'HOD has not entered marks', 8, '{"course":"CS301"}',
                                '[{"person_id":102,"party_role":"Respondent"}]');   -- -> Dean Academics
  PERFORM set_config('app.now', (now() + interval '6 days')::text, true);
  PERFORM escalate_overdue();
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Student Grievance Redressal Committee',
                     'academic complaint escalates from the Dean Academics to the SGRC');

  -- 7. Stale information requests are closed after 7 days
  PERFORM set_config('app.now', '', true);
  v_id := pg_temp.new_complaint(1006, 'projector broken', 5, '{"item":"projector"}');   -- NeedsInfo
  PERFORM set_config('app.now', (now() + interval '8 days')::text, true);
  PERFORM close_stale_needs_info(7);
  PERFORM pg_temp.ok((SELECT status = 'Closed' AND resolution_outcome = 'InsufficientInfo'
                      FROM complaint WHERE complaint_id = v_id),
                     'no reply for 7 days -> closed as InsufficientInfo');

  -- 8. Resolve, then reopen once (within 7 days)
  PERFORM set_config('app.now', '', true);
  v_id := pg_temp.new_complaint(1001, 'fan broken', 2, '{"room_or_floor":"room 214"}');
  PERFORM pg_temp.act_as(203);
  UPDATE complaint SET status = 'InProgress' WHERE complaint_id = v_id;
  UPDATE complaint SET status = 'Resolved', resolution_outcome = 'Fixed' WHERE complaint_id = v_id;
  PERFORM pg_temp.ok((SELECT resolved_at IS NOT NULL FROM complaint WHERE complaint_id = v_id),
                     'resolved_at stamped automatically on resolution');
  PERFORM pg_temp.act_as(1001);
  v_new := reopen_complaint(v_id, 'Fan stopped again the same night');
  PERFORM pg_temp.ok((SELECT reopened_from FROM complaint WHERE complaint_id = v_new) = v_id
                     AND (SELECT status FROM complaint WHERE complaint_id = v_new) = 'Assigned'
                     AND (SELECT status FROM complaint WHERE complaint_id = v_id) = 'Closed',
                     'reopen creates a linked complaint (recursive FK) and routes it again');
  BEGIN
    PERFORM reopen_complaint(v_id, 'again');
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err = 'A complaint can only be reopened once', 'a complaint can be reopened only once');

  -- 9. Appeal to the Ombudsperson, then decision
  v_id := pg_temp.new_complaint(1001, 'teacher biased in grading', 11, '{}',
            '[{"person_id":105,"party_role":"Respondent"}]', 'Medium', 0.9, TRUE);
  PERFORM pg_temp.act_as(131);                                   -- SGRC chair
  UPDATE complaint SET status = 'InProgress' WHERE complaint_id = v_id;
  UPDATE complaint SET status = 'Resolved', resolution_outcome = 'Dismissed' WHERE complaint_id = v_id;
  PERFORM pg_temp.act_as(1001);
  v_appeal := file_appeal(v_id, 'Evidence was not considered');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Appealed'
                     AND (SELECT heard_by FROM appeal WHERE appeal_id = v_appeal) = 172,
                     'appeal filed and assigned to the Ombudsperson');
  PERFORM pg_temp.act_as(172);
  PERFORM decide_appeal(v_appeal, 'Dismissed', 'Committee decision upheld');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Closed',
                     'dismissed appeal closes the complaint');

  -- 10. Appeal window: too late after the window
  v_id := pg_temp.new_complaint(1001, 'teacher biased again', 11, '{}',
            '[{"person_id":105,"party_role":"Respondent"}]', 'Medium', 0.9, TRUE);
  PERFORM pg_temp.act_as(131);
  UPDATE complaint SET status = 'InProgress' WHERE complaint_id = v_id;
  UPDATE complaint SET status = 'Resolved', resolution_outcome = 'Dismissed' WHERE complaint_id = v_id;
  PERFORM set_config('app.now', (now() + interval '40 days')::text, true);
  PERFORM pg_temp.act_as(1001);
  BEGIN
    PERFORM file_appeal(v_id, 'late');
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'The 30 day appeal window has passed', 'appeals after the window are refused');
END $$;
ROLLBACK;
