-- Routing, priority and the completeness check.
\echo '--- test_routing ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE v_id int; v_st text; v_open int; v_seq int; v_due timestamptz;
BEGIN
  -- 1. Hinglish water complaint from Aarav (BH-3, room 214) without naming the
  --    hostel: hostel and room are filled from his profile, then routed.
  v_id := pg_temp.new_complaint(1001, 'washroom mein paani nahi aa raha', 1, '{}');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Assigned',
                     'complete water complaint is routed straight away');
  PERFORM pg_temp.ok((SELECT value FROM complaint_detail WHERE complaint_id = v_id AND field_name = 'hostel') = 'BH-3'
                     AND (SELECT source FROM complaint_detail WHERE complaint_id = v_id AND field_name = 'hostel') = 'Profile',
                     'missing hostel filled from the student profile (source = Profile)');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dinesh Kumar', 'water complaint in BH-3 goes to the BH-3 caretaker');

  -- 2. Priority: base Medium + AI urgency High -> High; base Medium + AI Low -> stays Medium
  v_id := pg_temp.new_complaint(1001, 'live wire hanging in the corridor', 2,
                                '{"room_or_floor":"2nd floor corridor"}', '[]', 'High');
  PERFORM pg_temp.ok((SELECT priority FROM complaint WHERE complaint_id = v_id) = 'High',
                     'AI urgency can RAISE priority (Medium -> High)');
  v_id := pg_temp.new_complaint(1001, 'tap is dripping slowly', 1,
                                '{"room_or_floor":"room 214"}', '[]', 'Low');
  PERFORM pg_temp.ok((SELECT priority FROM complaint WHERE complaint_id = v_id) = 'Medium',
                     'AI urgency can never LOWER priority below the category base');
  PERFORM pg_temp.ok(compute_priority(NULL, 'High') = 'High',
                     'General/Other (no base priority): AI urgency decides');

  -- 3. Deadline = category SLA (water: 24 hours)
  SELECT due_at INTO v_due FROM routing_decision WHERE decision_id = latest_decision(v_id);
  PERFORM pg_temp.ok(abs(extract(epoch FROM (v_due - (SELECT filed_at FROM complaint WHERE complaint_id = v_id))) - 24*3600) < 60,
                     'deadline set from the category SLA (24h)');

  -- 4. Building infrastructure -> Estate officer of that department's block
  v_id := pg_temp.new_complaint(1004, 'AC not working', 5, '{"building_room":"ECE block room 101"}');
  PERFORM pg_temp.ok((SELECT reason LIKE '%Estate Officer (ECE Block)%' FROM routing_decision
                      WHERE decision_id = latest_decision(v_id)),
                     'infrastructure complaint goes to the estate officer of the ECE block');

  -- 5. Lab equipment -> lab in-charge of the department
  v_id := pg_temp.new_complaint(1001, 'PCs not booting', 6, '{"lab_name":"CSE lab 3","equipment":"PCs"}');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Arjun Bhatia', 'lab complaint goes to the CSE lab in-charge');

  -- 6. Wi-Fi -> Computer Centre (a central post, no department)
  v_id := pg_temp.new_complaint(1003, 'wifi down', 10, '{"device_or_service":"Wi-Fi"}');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Rekha Jain', 'Wi-Fi complaint goes to the Computer Centre helpdesk');

  -- 7. Timetable clash -> timetable coordinator of the course's department
  v_id := pg_temp.new_complaint(1001, 'clash', 7, '{"course":"CS302","clash_details":"Tue 10am"}');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Dr. Neha Kapoor', 'timetable clash goes to the CSE timetable coordinator');

  -- 8. General / Other -> waits for the triage officer, then goes to the triage officer
  v_id := pg_temp.new_complaint(1001, 'library closes too early', 15, '{}', '[]', 'Low', 0.4);
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Filed'
                     AND (SELECT category_id FROM complaint WHERE complaint_id = v_id) IS NULL,
                     'low-confidence complaint waits in the triage queue');
  PERFORM pg_temp.act_as(210);
  PERFORM confirm_triage(v_id, 15, 'Low');
  PERFORM pg_temp.ok(pg_temp.assignee(v_id) = 'Pallavi Gupta'
                     AND (SELECT reviewed_by FROM ai_triage_result WHERE complaint_id = v_id) = 210,
                     'triage officer confirms; General/Other is handled by the triage officer');
  PERFORM pg_temp.ok((SELECT due_at - decided_at FROM routing_decision WHERE decision_id = latest_decision(v_id)) = interval '48 hours',
                     'General/Other Low priority gets the 48h default deadline');

  -- 9. A confident AI category is accepted automatically (no human needed)
  v_id := pg_temp.new_complaint(1003, 'fan broken', 2, '{"room_or_floor":"305"}', '[]', 'Low', 0.95);
  PERFORM pg_temp.ok((SELECT reviewed_by FROM ai_triage_result WHERE complaint_id = v_id) IS NULL
                     AND (SELECT category_id FROM complaint WHERE complaint_id = v_id) = 2,
                     'confident AI category (>= 0.70) accepted automatically');
END $$;

-- ---------------------------------------------------------------------
-- Completeness check and clarifications
-- ---------------------------------------------------------------------
DO $$
DECLARE v_id int; v_seq int; v_res text;
BEGIN
  -- 10. Vague projector complaint without a room -> NeedsInfo with the stored question
  v_id := pg_temp.new_complaint(1006, 'projector not working', 5, '{"item":"projector"}');
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'NeedsInfo',
                     'complaint missing a mandatory detail goes to NeedsInfo');
  PERFORM pg_temp.ok((SELECT field_name FROM check_completeness(v_id)) = 'building_room',
                     'check_completeness() reports the missing field (building_room)');
  SELECT seq_no INTO v_seq FROM clarification WHERE complaint_id = v_id AND answer IS NULL;
  PERFORM pg_temp.ok((SELECT question FROM clarification WHERE complaint_id = v_id AND seq_no = v_seq)
                     = 'Which building and room number?',
                     'the question asked is the one stored in CategoryRequirement');

  -- 11. Answering it completes the complaint and routes it
  PERFORM pg_temp.act_as(1006);
  v_res := answer_clarification(v_id, v_seq, 'CSE block room 204');
  PERFORM pg_temp.ok(v_res = 'Assigned' AND NOT EXISTS (SELECT 1 FROM check_completeness(v_id)),
                     'answer stored as a detail; complaint is now complete and routed');
  PERFORM pg_temp.ok((SELECT source FROM complaint_detail WHERE complaint_id = v_id AND field_name = 'building_room') = 'User',
                     'answered detail recorded with source = User');

  -- 12. Sensitive complaint with only the respondent's role is NEVER blocked
  v_id := pg_temp.new_complaint(1002, 'someone is harassing me', 12, '{}',
            '[{"party_role":"Respondent","stated_role":"Unknown","description":"not sure who"}]',
            'High', 0.7, TRUE);
  PERFORM pg_temp.ok((SELECT status FROM complaint WHERE complaint_id = v_id) = 'Assigned',
                     'sensitive complaint routed even with almost no details');
  PERFORM pg_temp.ok((SELECT visibility FROM complaint WHERE complaint_id = v_id) = 'Confidential',
                     'sensitive complaint filed as Public is forced to Confidential');

  -- 13. Sensitive complaint with NO respondent role at all -> asks the role question
  v_id := pg_temp.new_complaint(1002, 'I am being harassed', 12, '{}', '[]', 'High', 0.9, TRUE);
  PERFORM pg_temp.ok((SELECT question FROM clarification WHERE complaint_id = v_id)
                     LIKE 'Is the person a student, faculty member%',
                     'only the respondent-role question is asked for a sensitive complaint');

  -- 14. "Ram" -> candidates, the teacher of her own course first
  PERFORM pg_temp.act_as(1002);
  PERFORM pg_temp.ok((SELECT full_name FROM find_person_candidates('Ram', 'Faculty') LIMIT 1) = 'Dr. Ram Kumar'
                     AND (SELECT connection FROM find_person_candidates('Ram', 'Faculty') LIMIT 1)
                         = 'Teaches your course Database Management Systems',
                     'person matching ranks "Ram" who teaches her course first');
  PERFORM pg_temp.ok((SELECT count(*) FROM find_person_candidates('Ram', 'Faculty')) >= 2,
                     'other matching people (Dr. Ramesh Kumar) are also suggested');
END $$;
ROLLBACK;
