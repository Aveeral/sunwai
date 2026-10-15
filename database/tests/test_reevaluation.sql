-- Answer-script re-evaluation (exam module).
\echo '--- test_reevaluation ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE v_id int; v_err text; v_script int; v_before numeric; v_reviewer int;
BEGIN
  SELECT script_id, total_marks INTO v_script, v_before
  FROM answer_script WHERE exam_id = 1 AND student_id = 1002;     -- Riya, DBMS, evaluator Dr. Ram Kumar

  -- 1. Only the student who wrote the script can request re-evaluation
  PERFORM pg_temp.act_as(1001);
  BEGIN
    PERFORM file_reevaluation(v_script, '[{"question_no":1,"marks_awarded":1,"marks_claimed":3,"reason":"x"}]');
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'You can only request re-evaluation of your own%',
                     'a student cannot request re-evaluation of someone else''s script');

  -- 2. Filing creates a complaint routed to the CoE, then to an independent reviewer
  PERFORM pg_temp.act_as(1002);
  v_id := file_reevaluation(v_script,
     '[{"question_no":2,"marks_awarded":3,"marks_claimed":6,"reason":"correct ER diagram"},
       {"question_no":4,"marks_awarded":1,"marks_claimed":3,"reason":"query is right"}]');
  PERFORM pg_temp.ok((SELECT count(*) FROM routing_decision WHERE complaint_id = v_id) = 2
                     AND (SELECT reason FROM routing_decision WHERE complaint_id = v_id AND decision_type = 'Initial')
                         LIKE '%Controller of Examinations%',
                     'routed first to the Controller of Examinations, then to a reviewer');
  PERFORM pg_temp.ok((SELECT count(*) FROM question_dispute WHERE complaint_id = v_id) = 2,
                     'one QuestionDispute row per disputed question (weak entity)');
  v_reviewer := (SELECT assigned_person_id FROM routing_decision WHERE decision_id = latest_decision(v_id));
  PERFORM pg_temp.ok(v_reviewer <> 101
                     AND (SELECT unit_id FROM person WHERE person_id = v_reviewer) = 2,
                     'reviewer is from the course''s department (CSE) and is not the evaluator');

  -- 3. Trigger: assigning the original evaluator directly is impossible
  BEGIN
    INSERT INTO routing_decision (complaint_id, assigned_person_id, decision_type, reason, decided_at)
    VALUES (v_id, 101, 'Manual', 'try to give it to the evaluator', now());
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'The original evaluator cannot review%',
                     'trigger blocks assigning the original evaluator as reviewer');

  -- 4. Only the assigned reviewer can decide
  PERFORM pg_temp.act_as(101);
  BEGIN
    PERFORM decide_dispute(v_id, 2, 'Accepted', 6);
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'Only the assigned reviewer%', 'the evaluator cannot decide the dispute');

  -- 5. Reviewer accepts Q2 (3 -> 6): mark change logged, total updated
  PERFORM pg_temp.act_as(v_reviewer);
  PERFORM decide_dispute(v_id, 2, 'Accepted', 6);
  PERFORM pg_temp.ok((SELECT old_marks = 3 AND new_marks = 6 AND changed_by = v_reviewer
                      FROM marks_change_log WHERE complaint_id = v_id AND question_no = 2),
                     'MarksChangeLog records old 3 -> new 6 and who changed it');
  PERFORM pg_temp.ok((SELECT total_marks FROM answer_script WHERE script_id = v_script) = v_before + 3,
                     'answer script total updated by +3');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'InProgress',
                     'still in progress while a question is undecided');

  -- 6. Reject Q4: no mark change logged; all decided -> resolved, outcome Upheld
  PERFORM decide_dispute(v_id, 4, 'Rejected', NULL);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM marks_change_log WHERE complaint_id = v_id AND question_no = 4),
                     'rejected question: marks unchanged, nothing logged');
  PERFORM pg_temp.ok((SELECT status = 'Resolved' AND resolution_outcome = 'Upheld'
                      FROM complaint WHERE complaint_id = v_id),
                     'all questions decided -> re-evaluation resolved automatically (Upheld)');

  -- 7. The mark log can never be altered
  BEGIN
    UPDATE marks_change_log SET new_marks = 10 WHERE complaint_id = v_id;
    v_err := NULL;
  EXCEPTION WHEN raise_exception THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.ok(v_err LIKE 'marks_change_log is append-only%', 'mark change log is append-only');
END $$;
ROLLBACK;
