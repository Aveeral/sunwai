-- =====================================================================
--  08_seed_demo.sql : demo data
--  Students, courses, enrolments, exams, answer scripts, and about 60
--  complaints spread over the last 8 weeks.
--
--  Complaints are NOT inserted directly: each one is filed and moved
--  through the real procedures (file_complaint, record_ai_triage,
--  route_complaint, escalate_overdue ...) with the clock set back in time
--  (app.now). So every status history row, routing decision and conflict
--  exclusion in the demo data was produced by the real logic.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Named demo students (used in the showcase walkthrough)
-- ---------------------------------------------------------------------
INSERT INTO person (person_id, first_name, last_name, email, phone, person_type, unit_id) VALUES
 (1001,'Aarav','Mehta','aarav.mehta@nsut.ac.in','9900001001','Student',2),
 (1002,'Riya','Sharma','riya.sharma@nsut.ac.in','9900001002','Student',2),
 (1003,'Ishaan','Verma','ishaan.verma@nsut.ac.in','9900001003','Student',3),
 (1004,'Ananya','Singh','ananya.singh@nsut.ac.in','9900001004','Student',4),
 (1005,'Kabir','Khanna','kabir.khanna@nsut.ac.in','9900001005','Student',5),
 (1006,'Sneha','Gupta','sneha.gupta@nsut.ac.in','9900001006','Student',2);

INSERT INTO student (person_id, roll_no, programme, batch_year, hostel_unit_id, room_no) VALUES
 (1001,'2024UCS1001','B.Tech CSE',2024,22,'214'),   -- BH-3
 (1002,'2024UCS1002','B.Tech CSE',2024,23,'108'),   -- GH-1
 (1003,'2023UIT1003','B.Tech IT', 2023,21,'305'),   -- BH-2
 (1004,'2025UEC1004','B.Tech ECE',2025,23,'112'),   -- GH-1
 (1005,'2025UME1005','B.Tech ME', 2025,20,'021'),   -- BH-1 (fresher)
 (1006,'2024UCS1006','B.Tech CSE',2024,NULL,NULL);  -- day scholar

-- ---------------------------------------------------------------------
-- 2. 94 more students, generated
-- ---------------------------------------------------------------------
DO $$
DECLARE
  boys  text[] := ARRAY['Rohan','Aditya','Vivaan','Arjun','Kunal','Siddharth','Yash','Dev',
                        'Harsh','Nikhil','Pranav','Rahul','Varun','Akash','Manav','Tanmay'];
  girls text[] := ARRAY['Aditi','Diya','Isha','Kavya','Meera','Nisha','Pooja','Saanvi',
                        'Tanya','Kriti','Neha','Shreya','Simran','Avni','Myra','Ira'];
  lasts text[] := ARRAY['Agarwal','Bansal','Chauhan','Dutta','Garg','Jain','Kapoor','Malhotra',
                        'Nair','Pandey','Reddy','Saxena','Tiwari','Yadav','Bhatia','Mishra'];
  depts int[]  := ARRAY[2,2,3,4,5,7];
  progs text[] := ARRAY['B.Tech CSE','B.Tech CSE','B.Tech IT','B.Tech ECE','B.Tech ME','B.Tech Civil'];
  codes text[] := ARRAY['UCS','UCS','UIT','UEC','UME','UCE'];
  i int; k int; female boolean; fn text; ln text; v_hostel int; v_batch int;
BEGIN
  FOR i IN 1007..1100 LOOP
    k := 1 + (i % 6);
    female := (i % 3 = 0);
    fn := CASE WHEN female THEN girls[1 + (i % 16)] ELSE boys[1 + (i % 16)] END;
    ln := lasts[1 + ((i * 7) % 16)];
    v_batch := 2023 + (i % 3);
    v_hostel := CASE
                  WHEN i % 5 = 0 THEN NULL                       -- day scholar
                  WHEN depts[k] = 7 THEN 24                      -- West campus
                  WHEN female THEN 23
                  ELSE 20 + (i % 3)                              -- BH-1/2/3
                END;
    INSERT INTO person (person_id, first_name, last_name, email, phone, person_type, unit_id)
    VALUES (i, fn, ln, lower(fn || '.' || ln || '.' || i || '@nsut.ac.in'),
            '99000' || lpad(i::text, 5, '0'), 'Student', depts[k]);
    INSERT INTO student (person_id, roll_no, programme, batch_year, hostel_unit_id, room_no)
    VALUES (i, v_batch || codes[k] || i, progs[k], v_batch, v_hostel,
            CASE WHEN v_hostel IS NULL THEN NULL ELSE (100 + (i * 13) % 300)::text END);
  END LOOP;
END $$;

-- Student special invitees on committees (UGC 2023 rules)
INSERT INTO committee_member (committee_id, person_id, member_role, term_start, term_end) VALUES
 (1, 1004, 'StudentInvitee', '2026-07-01', '2027-06-30'),
 (2, 1003, 'StudentInvitee', '2026-07-01', '2027-06-30'),
 (3, 1003, 'StudentInvitee', '2026-07-01', '2027-06-30');

-- ---------------------------------------------------------------------
-- 3. Courses, offerings, enrolments
-- ---------------------------------------------------------------------
INSERT INTO course (course_code, title, credits, unit_id) VALUES
 ('CS301','Database Management Systems',4,2),
 ('CS302','Operating Systems',4,2),
 ('CS303','Computer Networks',4,2),
 ('CS304','Machine Learning',4,2),
 ('IT301','Software Engineering',4,3),
 ('IT302','Web Technologies',3,3),
 ('EC301','Digital Signal Processing',4,4),
 ('EC302','VLSI Design',4,4),
 ('ME301','Thermodynamics',4,5),
 ('MA201','Probability and Statistics',3,6),
 ('CE301','Structural Analysis',4,7);

INSERT INTO course_offering (offering_id, course_code, faculty_id, semester, section) VALUES
 (1,'CS301',101,'2026-Odd','A'),
 (2,'CS302',103,'2026-Odd','A'),
 (3,'CS303',105,'2026-Odd','A'),
 (4,'CS304',106,'2026-Odd','A'),
 (5,'IT301',112,'2026-Odd','A'),
 (6,'IT302',113,'2026-Odd','A'),
 (7,'EC301',122,'2026-Odd','A'),
 (8,'EC302',123,'2026-Odd','A'),
 (9,'ME301',132,'2026-Odd','A'),
 (10,'MA201',142,'2026-Odd','A'),
 (11,'CE301',152,'2026-Odd','A');
SELECT setval(pg_get_serial_sequence('sunwai.course_offering','offering_id'), 100);

-- every student takes their department's courses plus MA201
INSERT INTO enrollment (student_id, offering_id)
SELECT s.person_id, o.offering_id
FROM student s
JOIN person p USING (person_id)
JOIN course_offering o ON TRUE
JOIN course c ON c.course_code = o.course_code
WHERE c.unit_id = p.unit_id OR c.course_code = 'MA201';

-- ---------------------------------------------------------------------
-- 4. Mid-semester exams and answer scripts
-- ---------------------------------------------------------------------
INSERT INTO exam (exam_id, offering_id, exam_type, exam_date, max_marks) VALUES
 (1, 1, 'MidSem', '2026-09-22', 30),   -- DBMS
 (2, 2, 'MidSem', '2026-09-23', 30),   -- OS
 (3, 5, 'MidSem', '2026-09-22', 30),   -- Software Engineering
 (4, 7, 'MidSem', '2026-09-24', 30),   -- DSP
 (5, 10,'MidSem', '2026-09-25', 30);   -- Probability and Statistics
SELECT setval(pg_get_serial_sequence('sunwai.exam','exam_id'), 100);

INSERT INTO answer_script (exam_id, student_id, evaluator_id, total_marks, shown_on)
SELECT e.exam_id, en.student_id, o.faculty_id,
       12 + ((en.student_id * 7 + e.exam_id * 3) % 17),
       e.exam_date + 14
FROM exam e
JOIN course_offering o ON o.offering_id = e.offering_id
JOIN enrollment en ON en.offering_id = e.offering_id;

-- =====================================================================
-- 5. COMPLAINTS
-- =====================================================================

-- Helper: file + AI-triage a complaint as a given person at a given time.
CREATE OR REPLACE FUNCTION pg_temp.seed_file(p_person int, p_at timestamptz, p_text text,
        p_vis text, p_cat int, p_urg text, p_conf numeric, p_sens boolean, p_summary text,
        p_details jsonb, p_parties jsonb DEFAULT '[]')
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_id int;
BEGIN
  PERFORM set_config('app.now', p_at::text, false);
  PERFORM set_config('app.user_id', p_person::text, false);
  v_id := sunwai.file_complaint(p_text, p_vis, TRUE);
  PERFORM sunwai.record_ai_triage(v_id, p_cat, p_urg, p_conf, p_sens, p_summary, p_details, p_parties);
  RETURN v_id;
END $$;

-- Helper: act as the current handler and change the status.
CREATE OR REPLACE FUNCTION pg_temp.seed_status(p_id int, p_at timestamptz, p_status text,
        p_outcome text DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_handler int;
BEGIN
  SELECT coalesce(d.assigned_person_id,
                  (SELECT m.person_id FROM sunwai.committee_member m
                   WHERE m.committee_id = d.assigned_committee_id
                     AND m.member_role = 'Chair' LIMIT 1))
    INTO v_handler
  FROM sunwai.routing_decision d WHERE d.decision_id = sunwai.latest_decision(p_id);
  PERFORM set_config('app.now', p_at::text, false);
  PERFORM set_config('app.user_id', v_handler::text, false);
  PERFORM set_config('app.status_note', coalesce(p_note, ''), false);
  UPDATE sunwai.complaint
     SET status = p_status,
         resolution_outcome = coalesce(p_outcome, resolution_outcome),
         resolution_note = CASE WHEN p_status IN ('Resolved','Rejected') THEN coalesce(p_note, resolution_note)
                                ELSE resolution_note END
   WHERE complaint_id = p_id;
  PERFORM set_config('app.status_note', '', false);
END $$;

-- Helper: full happy path - in progress after h1 hours, resolved after h2,
-- optionally rated by the complainant afterwards.
CREATE OR REPLACE FUNCTION pg_temp.seed_resolve(p_id int, p_h1 numeric, p_h2 numeric,
        p_note text, p_rating int DEFAULT NULL, p_outcome text DEFAULT 'Fixed')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_filed timestamptz; v_owner int;
BEGIN
  SELECT filed_at INTO v_filed FROM sunwai.complaint WHERE complaint_id = p_id;
  PERFORM pg_temp.seed_status(p_id, v_filed + make_interval(secs => p_h1 * 3600), 'InProgress');
  PERFORM pg_temp.seed_status(p_id, v_filed + make_interval(secs => p_h2 * 3600), 'Resolved', p_outcome, p_note);
  IF p_rating IS NOT NULL THEN
    SELECT person_id INTO v_owner FROM sunwai.complainant_identity WHERE complaint_id = p_id;
    PERFORM set_config('app.now', (v_filed + make_interval(secs => (p_h2 + 3) * 3600))::text, false);
    PERFORM set_config('app.user_id', v_owner::text, false);
    PERFORM sunwai.rate_and_close(p_id, p_rating);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 5a. Background history: ~45 everyday complaints over the last 8 weeks,
--     mostly resolved, some escalated, a few corrected by the triage officer.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  -- category, description, details, resolution note, base hours to fix
  tpl jsonb := '[
   {"cat":1,"txt":"No water in the washroom taps on our floor since morning","det":{"room_or_floor":"2nd floor washroom","since_when":"this morning"},"fix":"Pump valve repaired","h":10},
   {"cat":1,"txt":"Water cooler near the stairs is leaking and the floor is flooded","det":{"room_or_floor":"ground floor near stairs"},"fix":"Cooler pipe replaced","h":8},
   {"cat":2,"txt":"Tube light and fan in my room stopped working after the power cut","det":{"room_or_floor":"own room","since_when":"last night"},"fix":"MCB reset and fan capacitor replaced","h":12},
   {"cat":2,"txt":"Corridor lights on the third floor are not working, it is completely dark at night","det":{"room_or_floor":"3rd floor corridor"},"fix":"Corridor bulbs replaced","h":20},
   {"cat":3,"txt":"Washrooms on our floor have not been cleaned for three days","det":{"room_or_floor":"1st floor washrooms"},"fix":"Cleaning staff rescheduled","h":30},
   {"cat":3,"txt":"The study table in my room is broken, one leg came off","det":{"room_or_floor":"own room"},"fix":"Table replaced","h":50},
   {"cat":4,"txt":"Found an insect in the dal at dinner, hygiene in the mess kitchen is poor","det":{"meal":"dinner dal","meal_date":"yesterday"},"fix":"Kitchen inspected, vendor warned","h":30},
   {"cat":4,"txt":"Breakfast is served cold almost every day this week","det":{"meal":"breakfast"},"fix":"Breakfast timing adjusted","h":40},
   {"cat":5,"txt":"The AC in classroom CSE block room 204 is not cooling at all","det":{"building_room":"CSE block room 204","item":"AC"},"fix":"AC gas refilled","h":40},
   {"cat":5,"txt":"Projector mount in ECE block room 101 is loose and shaking","det":{"building_room":"ECE block room 101","item":"projector mount"},"fix":"Mount tightened","h":30},
   {"cat":6,"txt":"Half the PCs in the CSE programming lab do not boot","det":{"lab_name":"CSE programming lab 2","equipment":"desktop PCs"},"fix":"Reimaged 14 PCs","h":30},
   {"cat":6,"txt":"Oscilloscopes in the ECE circuits lab are giving no signal","det":{"lab_name":"ECE circuits lab","equipment":"oscilloscopes"},"fix":"Probes replaced","h":36},
   {"cat":7,"txt":"Our CS302 lecture clashes with the MA201 tutorial on Tuesday","det":{"course":"CS302","clash_details":"Tuesday 10-11 am"},"fix":"Tutorial moved to Thursday","h":48},
   {"cat":8,"txt":"My attendance in Software Engineering is shown as 60% but I attended every class","det":{"course":"IT301","assessment":"attendance"},"fix":"Attendance corrected after register check","h":80},
   {"cat":10,"txt":"Hostel Wi-Fi keeps disconnecting every few minutes","det":{"device_or_service":"Hostel Wi-Fi","location":"hostel"},"fix":"Access point replaced","h":30},
   {"cat":10,"txt":"IMS portal shows an error when I try to download my fee receipt","det":{"device_or_service":"IMS portal"},"fix":"Portal bug fixed by vendor","h":40}
  ]';
  t jsonb; i int; v_cat int; v_person int; v_at timestamptz; v_id int; v_det jsonb;
  v_hostel text; v_conf numeric; v_aicat int; v_rating int; v_hours numeric;
BEGIN
  FOR i IN 0..44 LOOP
    t := tpl->(i % 16);
    v_cat := (t->>'cat')::int;
    -- pick a hosteller for hostel/mess complaints, anyone otherwise
    SELECT s.person_id INTO v_person
    FROM sunwai.student s JOIN sunwai.person p USING (person_id)
    WHERE (v_cat NOT IN (1,2,3,4) OR s.hostel_unit_id IS NOT NULL)
      AND (v_cat NOT IN (5,6,7,8) OR p.unit_id IN (2,3,4))
      AND s.person_id > 1006
    ORDER BY (s.person_id * 31 + i * 17) % 97
    LIMIT 1;

    v_det := t->'det';
    IF v_cat IN (1,2,3,4) THEN
      SELECT d.name INTO v_hostel FROM sunwai.student s JOIN sunwai.department d
        ON d.unit_id = s.hostel_unit_id WHERE s.person_id = v_person;
      -- every other one names the hostel; the rest rely on the profile
      IF i % 2 = 0 THEN v_det := v_det || jsonb_build_object('hostel', v_hostel); END IF;
    END IF;

    v_at := date_trunc('hour', now()) - make_interval(days => 56 - i)
            + make_interval(hours => (i * 5) % 11);
    -- the AI is usually right; every 7th time it guesses wrong with low confidence
    IF i % 7 = 3 THEN
      v_conf := 0.55; v_aicat := CASE WHEN v_cat = 10 THEN 5 ELSE 15 END;
    ELSE
      v_conf := 0.80 + (i % 4) * 0.05; v_aicat := v_cat;
    END IF;

    v_id := pg_temp.seed_file(v_person, v_at, t->>'txt', 'Public', v_aicat,
                              CASE WHEN i % 9 = 0 THEN 'High' ELSE 'Low' END,
                              v_conf, FALSE, left(t->>'txt', 80), v_det);

    -- low-confidence ones are corrected by the triage officer an hour later
    IF v_conf < 0.70 THEN
      PERFORM set_config('app.now', (v_at + interval '1 hour')::text, false);
      PERFORM set_config('app.user_id', '210', false);
      PERFORM sunwai.confirm_triage(v_id, v_cat);
    END IF;

    v_hours := (t->>'h')::numeric * (0.6 + (i % 5) * 0.2);
    -- every 6th complaint misses its deadline and is escalated first
    IF i % 6 = 5 THEN
      PERFORM set_config('app.now', (v_at + make_interval(hours =>
          (SELECT coalesce(sla_hours, 48) FROM sunwai.category WHERE category_id = v_cat) + 2))::text, false);
      PERFORM sunwai.escalate_overdue();
      v_hours := (SELECT coalesce(sla_hours, 48) FROM sunwai.category WHERE category_id = v_cat) + 10;
    END IF;

    v_rating := CASE WHEN i % 4 = 0 THEN NULL ELSE 3 + (i % 3) END;
    PERFORM pg_temp.seed_resolve(v_id, 2, v_hours, t->>'fix', v_rating);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 5b. Showcase complaints (left in useful states for the live demo)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_id int; v_now timestamptz := date_trunc('minute', now());
BEGIN
  -- S1. Four recent water complaints from BH-3 2nd floor (a hotspot);
  --     two resolved, two open with the caretaker.
  FOR i IN 1..4 LOOP
    v_id := pg_temp.seed_file(
      (SELECT person_id FROM sunwai.student WHERE hostel_unit_id = 22 AND person_id > 1006
       ORDER BY person_id OFFSET i - 1 LIMIT 1),
      v_now - make_interval(hours => 60 - i * 12),
      'BH-3 2nd floor washroom mein paani nahi aa raha',
      'Public', 1, 'Medium', 0.92, FALSE, 'No water in BH-3 second floor washroom',
      '{"hostel":"BH-3","room_or_floor":"2nd floor washroom"}');
    IF i <= 2 THEN PERFORM pg_temp.seed_resolve(v_id, 1, 6, 'Overhead tank valve fixed', 4); END IF;
  END LOOP;

  -- S2. Sexual harassment complaint about Dr. Ram Kumar (CSE) -> ICC.
  --     ICC member Dr. Vikram Sethi (also CSE) is recused automatically.
  v_id := pg_temp.seed_file(1002, v_now - interval '20 hours',
    'The professor who teaches our DBMS course keeps making inappropriate personal comments about me during lab sessions.',
    'Confidential', 12, 'High', 0.88, TRUE,
    'Repeated inappropriate personal remarks by a course instructor during lab sessions',
    '{"incident_details":"Inappropriate personal comments during DBMS lab sessions","incident_date":"last two weeks"}',
    '[{"person_id":101,"party_role":"Respondent","stated_role":"Faculty"}]');
  PERFORM pg_temp.seed_status(v_id, v_now - interval '10 hours', 'InProgress', NULL, 'Inquiry started');

  -- S3. Internal marks complaint naming the HOD of CSE.
  --     Normal route is the HOD -> she is the respondent -> goes to Dean Academics.
  v_id := pg_temp.seed_file(1006, v_now - interval '30 hours',
    'Prof. Sunita Rao has not entered my internal assessment marks for the CSE seminar course even after three reminders.',
    'Public', 8, 'Medium', 0.84, FALSE,
    'Internal marks not entered by the HOD despite reminders',
    '{"course":"CS301","assessment":"seminar internal marks"}',
    '[{"person_id":102,"party_role":"Respondent","stated_role":"Faculty"}]');

  -- S4. Faculty conduct complaint about the HOD of CSE -> SGRC.
  --     Dr. Neha Kapoor (CSE timetable coordinator) reports to the HOD -> recused.
  v_id := pg_temp.seed_file(1001, v_now - interval '3 days',
    'The HOD publicly insulted our whole section in the department meeting and threatened to fail us in practicals.',
    'Confidential', 11, 'High', 0.81, TRUE,
    'HOD allegedly insulted a section and threatened failing grades',
    '{"incident_details":"Public insults and threats in a department meeting"}',
    '[{"person_id":102,"party_role":"Respondent","stated_role":"Faculty"}]');

  -- S5. Ragging complaint by a fresher; seniors not identified -> Anti-Ragging Committee.
  v_id := pg_temp.seed_file(1005, v_now - interval '6 hours',
    'Some seniors in BH-1 forced us freshers to stand outside our rooms at 2 am and do push-ups. I do not know their names.',
    'Anonymous', 13, 'High', 0.95, TRUE,
    'Freshers forced to perform physical tasks at night by unidentified seniors in BH-1',
    '{"location":"BH-1 corridor","incident_date":"last night"}',
    '[{"party_role":"Respondent","stated_role":"Student","description":"Unidentified seniors in BH-1"}]');

  -- S6. Wi-Fi complaint untouched for 3 days (deadline 48h) -> ready to escalate live.
  v_id := pg_temp.seed_file(1003, v_now - interval '3 days',
    'Wi-Fi in BH-2 does not work at all on the 3rd floor since Monday.',
    'Public', 10, 'Low', 0.90, FALSE, 'No Wi-Fi on BH-2 third floor',
    '{"device_or_service":"Hostel Wi-Fi","location":"BH-2 3rd floor"}');

  -- S7. Mess complaint that already missed its deadline and was escalated
  --     from the Warden of BH-1 to the Chief Warden.
  v_id := pg_temp.seed_file(1047, v_now - interval '4 days',
    'Mess food in BH-1 has been stale for the last three days and many of us fell sick.',
    'Public', 4, 'High', 0.89, FALSE, 'Stale mess food in BH-1, students fell sick',
    '{"hostel":"BH-1","meal":"lunch and dinner","meal_date":"last three days"}');
  PERFORM set_config('app.now', (v_now - interval '4 days' + interval '50 hours')::text, false);
  PERFORM sunwai.escalate_overdue();

  -- S8. Vague infrastructure complaint without a room -> waiting for details.
  v_id := pg_temp.seed_file(1004, v_now - interval '5 hours',
    'The projector in our classroom is not working again.',
    'Public', 5, 'Low', 0.83, FALSE, 'Classroom projector not working', '{"item":"projector"}');

  -- S9. Complaints waiting for the triage officer (AI not confident).
  v_id := pg_temp.seed_file(1063, v_now - interval '3 hours',
    'The library closes at 8 pm even during end-semester exams, there is no place to study at night.',
    'Public', 15, 'Low', 0.45, FALSE, 'Library hours too short during exams', '{}');
  v_id := pg_temp.seed_file(1081, v_now - interval '2 hours',
    'Someone has been taking money from our room when we go for classes.',
    'Public', 15, 'Medium', 0.52, FALSE, 'Repeated theft from a hostel room', '{}');

  -- S10. Discrimination complaint (sensitive, accepted despite medium confidence) -> SGRC.
  v_id := pg_temp.seed_file(1056, v_now - interval '26 hours',
    'A lab assistant refuses to let me use the equipment and makes remarks about my caste.',
    'Confidential', 14, 'High', 0.66, TRUE,
    'Lab assistant allegedly denies access and makes caste-based remarks',
    '{"incident_details":"Denied lab equipment, caste remarks"}',
    '[{"party_role":"Respondent","stated_role":"Staff","description":"Lab assistant in the ECE lab"}]');

  -- S11. Faculty conduct complaint dismissed by the SGRC and appealed.
  v_id := pg_temp.seed_file(1019, v_now - interval '9 days',
    'Our Software Engineering instructor regularly cancels classes without notice and then holds surprise quizzes.',
    'Confidential', 11, 'Medium', 0.80, TRUE,
    'Instructor cancels classes and holds surprise quizzes',
    '{"incident_details":"Frequent cancellations followed by surprise quizzes"}',
    '[{"person_id":112,"party_role":"Respondent","stated_role":"Faculty"}]');
  PERFORM pg_temp.seed_status(v_id, v_now - interval '7 days', 'InProgress', NULL, 'Hearing scheduled');
  PERFORM pg_temp.seed_status(v_id, v_now - interval '4 days', 'Resolved', 'Dismissed',
                              'Committee found the cancellations were notified on IMS.');
  PERFORM set_config('app.now', (v_now - interval '2 days')::text, false);
  PERFORM set_config('app.user_id', '1019', false);
  PERFORM sunwai.file_appeal(v_id, 'The IMS notices were posted after the classes were cancelled, not before.');

  -- S12. Electricity complaint resolved yesterday (can be reopened in the demo).
  v_id := pg_temp.seed_file(1001, v_now - interval '2 days',
    'The power socket near my bed sparks when I plug in my laptop charger.',
    'Public', 2, 'High', 0.91, FALSE, 'Sparking power socket in a hostel room',
    '{"since_when":"two days"}');
  PERFORM pg_temp.seed_resolve(v_id, 1, 26, 'Socket replaced');

  -- S13. Re-evaluation already completed (Ishaan, Software Engineering).
  PERFORM set_config('app.now', (v_now - interval '6 days')::text, false);
  PERFORM set_config('app.user_id', '1003', false);
  v_id := sunwai.file_reevaluation(
            (SELECT script_id FROM sunwai.answer_script WHERE exam_id = 3 AND student_id = 1003),
            '[{"question_no":2,"marks_awarded":3,"marks_claimed":5,"reason":"Step marks not given for the correct approach"},
              {"question_no":4,"marks_awarded":2,"marks_claimed":4,"reason":"Diagram was correct"}]');
  PERFORM set_config('app.now', (v_now - interval '4 days')::text, false);
  PERFORM set_config('app.user_id', (SELECT assigned_person_id::text FROM sunwai.routing_decision
                                     WHERE decision_id = sunwai.latest_decision(v_id)), false);
  PERFORM sunwai.decide_dispute(v_id, 2, 'Accepted', 5);
  PERFORM sunwai.decide_dispute(v_id, 4, 'Rejected', NULL);

  -- S14. Re-evaluation in progress (Aarav, DBMS) - reviewer still to decide.
  PERFORM set_config('app.now', (v_now - interval '1 day')::text, false);
  PERFORM set_config('app.user_id', '1001', false);
  v_id := sunwai.file_reevaluation(
            (SELECT script_id FROM sunwai.answer_script WHERE exam_id = 1 AND student_id = 1001),
            '[{"question_no":3,"marks_awarded":2,"marks_claimed":5,"reason":"Normalization answer matches the textbook solution"},
              {"question_no":5,"marks_awarded":4,"marks_claimed":6,"reason":"SQL query output is correct"}]');
END $$;

-- back to the real clock, no user
SELECT set_config('app.now', '', false), set_config('app.user_id', '', false),
       set_config('app.status_note', '', false);
