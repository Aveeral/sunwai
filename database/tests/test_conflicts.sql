-- Conflict-of-interest rules: one case for each of the five reasons,
-- plus the committee quorum fallback.
\echo '--- test_conflicts ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE v_id int; v_dec int;
BEGIN
  -- Rule 1 "Respondent": internal-marks complaint about the HOD of CSE.
  -- Normal route = HOD CSE; she is the respondent -> skipped up to Dean Academics.
  v_id := pg_temp.new_complaint(1006, 'HOD has not entered my marks', 8,
            '{"course":"CS301"}', '[{"person_id":102,"party_role":"Respondent"}]');
  v_dec := latest_decision(v_id);
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Alok Mishra',
                     'Respondent rule: HOD skipped, complaint goes up to the Dean Academics');
  PERFORM pg_temp.ok((SELECT reason_code FROM conflict_exclusion WHERE decision_id = v_dec AND person_id = 102) = 'Respondent',
                     'the skip is recorded in ConflictExclusion with reason Respondent');

  -- Rule 2 "ReportsToRespondent": complaint about the HOD of CSE to the SGRC.
  -- Dr. Neha Kapoor (CSE timetable coordinator) reports to the HOD -> recused.
  v_id := pg_temp.new_complaint(1001, 'HOD insulted our section', 11, '{}',
            '[{"person_id":102,"party_role":"Respondent"}]', 'High', 0.9, TRUE);
  v_dec := latest_decision(v_id);
  PERFORM pg_temp.ok((SELECT reason_code FROM conflict_exclusion WHERE decision_id = v_dec AND person_id = 104) = 'ReportsToRespondent',
                     'ReportsToRespondent rule: a subordinate of the respondent is recused (recursive query)');
  PERFORM pg_temp.ok(reports_to_person(203, 164) AND NOT reports_to_person(164, 203),
                     'reports_to_person(): BH-3 caretaker is below the Chief Warden, not the other way round');

  -- Rule 3 "Complainant": the BH-3 caretaker files a complaint about BH-3 water.
  -- He would normally handle it himself -> skipped to the Warden of BH-3.
  v_id := pg_temp.new_complaint(203, 'tank leaking', 1, '{"hostel":"BH-3","room_or_floor":"roof tank"}');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Sneha Bhatt'
                     AND (SELECT reason_code FROM conflict_exclusion
                          WHERE decision_id = latest_decision(v_id) AND person_id = 203) = 'Complainant',
                     'Complainant rule: the complainant never handles their own complaint');

  -- Rule 4 "SameDepartment": harassment complaint about Dr. Ram Kumar (CSE) to the ICC.
  -- ICC member Dr. Vikram Sethi is also CSE -> recused.
  v_id := pg_temp.new_complaint(1002, 'inappropriate comments in lab', 12, '{}',
            '[{"person_id":101,"party_role":"Respondent"}]', 'High', 0.9, TRUE);
  v_dec := latest_decision(v_id);
  PERFORM pg_temp.ok((SELECT reason_code FROM conflict_exclusion WHERE decision_id = v_dec AND person_id = 103) = 'SameDepartment',
                     'SameDepartment rule: committee member from the respondent''s department is recused');
  PERFORM pg_temp.ok(NOT is_committee_handler(v_id, 103) AND is_committee_handler(v_id, 141),
                     'the recused member cannot act on the case; other members can');

  -- Rule 5 "OriginalEvaluator": re-evaluation of a DBMS script evaluated by Dr. Ram Kumar
  PERFORM pg_temp.act_as(1002);
  v_id := file_reevaluation((SELECT script_id FROM answer_script WHERE exam_id = 1 AND student_id = 1002),
                            '[{"question_no":1,"marks_awarded":2,"marks_claimed":4,"reason":"correct"}]');
  PERFORM pg_temp.ok((SELECT assigned_person_id FROM routing_decision WHERE decision_id = latest_decision(v_id)) <> 101
                     AND EXISTS (SELECT 1 FROM conflict_exclusion WHERE decision_id = latest_decision(v_id)
                                 AND person_id = 101 AND reason_code = 'OriginalEvaluator'),
                     'OriginalEvaluator rule: the evaluator is never the re-evaluation reviewer');

  -- Quorum fallback: if recusals leave the ICC below quorum -> Ombudsperson
  UPDATE committee SET quorum = 5 WHERE committee_id = 1;
  v_id := pg_temp.new_complaint(1002, 'harassment again', 12, '{}',
            '[{"person_id":101,"party_role":"Respondent"}]', 'High', 0.9, TRUE);
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Ombudsperson'
                     AND (SELECT reason LIKE '%Quorum not met%' FROM routing_decision
                          WHERE decision_id = latest_decision(v_id)),
                     'quorum not met after recusal -> case referred to the Ombudsperson');
END $$;
ROLLBACK;
