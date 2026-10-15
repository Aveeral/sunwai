-- =====================================================================
--  02_seed_reference.sql : the (fictional) NSUT structure
--  Departments, hostels and offices, office holders, positions and their
--  reporting hierarchy, committees, complaint categories, completeness
--  rules and routing rules.  All names of people are fictional.
-- =====================================================================
SET search_path TO sunwai, public;
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Departments / hostels / offices (one tree under the University)
-- ---------------------------------------------------------------------
INSERT INTO department (unit_id, name, unit_type, campus, parent_unit_id) VALUES
 (1,  'NSUT',                                'University', 'Main', NULL),
 -- academic departments
 (2,  'Computer Science and Engineering',    'Academic',   'Main', 1),
 (3,  'Information Technology',              'Academic',   'Main', 1),
 (4,  'Electronics and Communication Engg.', 'Academic',   'Main', 1),
 (5,  'Mechanical Engineering',              'Academic',   'Main', 1),
 (6,  'Mathematics',                         'Academic',   'Main', 1),
 (7,  'Civil Engineering',                   'Academic',   'West', 1),
 -- central offices
 (10, 'Academic Section',                    'Office',     'Main', 1),
 (11, 'Examination Branch',                  'Office',     'Main', 1),
 (12, 'Estate and Maintenance Office',       'Office',     'Main', 1),
 (13, 'Computer Centre',                     'Office',     'Main', 1),
 (14, 'Registrar Office',                    'Office',     'Main', 1),
 (15, 'Dean Student Welfare Office',         'Office',     'Main', 1),
 (16, 'Grievance Triage Cell',               'Cell',       'Main', 1),
 (17, 'Hostel Administration',               'Office',     'Main', 1),
 (18, 'Proctor Office',                      'Office',     'Main', 1),
 -- hostels (under Hostel Administration)
 (20, 'BH-1',                                'Hostel',     'Main', 17),
 (21, 'BH-2',                                'Hostel',     'Main', 17),
 (22, 'BH-3',                                'Hostel',     'Main', 17),
 (23, 'GH-1',                                'Hostel',     'Main', 17),
 (24, 'West Campus Hostel',                  'Hostel',     'West', 17);

-- ---------------------------------------------------------------------
-- Faculty and staff who hold posts or sit on committees  (ids 100-299)
-- ---------------------------------------------------------------------
INSERT INTO person (person_id, first_name, last_name, email, phone, person_type, unit_id) VALUES
 -- Computer Science and Engineering
 (101,'Ram','Kumar','ram.kumar@nsut.ac.in','9810000101','Faculty',2),
 (102,'Sunita','Rao','sunita.rao@nsut.ac.in','9810000102','Faculty',2),
 (103,'Vikram','Sethi','vikram.sethi@nsut.ac.in','9810000103','Faculty',2),
 (104,'Neha','Kapoor','neha.kapoor@nsut.ac.in','9810000104','Faculty',2),
 (105,'Arjun','Bhatia','arjun.bhatia@nsut.ac.in','9810000105','Faculty',2),
 (106,'Ramesh','Kumar','ramesh.kumar@nsut.ac.in','9810000106','Faculty',2),
 -- Information Technology
 (111,'Meera','Iyer','meera.iyer@nsut.ac.in','9810000111','Faculty',3),
 (112,'Karan','Malhotra','karan.malhotra@nsut.ac.in','9810000112','Faculty',3),
 (113,'Pooja','Sinha','pooja.sinha@nsut.ac.in','9810000113','Faculty',3),
 -- Electronics and Communication
 (121,'Rajesh','Gupta','rajesh.gupta@nsut.ac.in','9810000121','Faculty',4),
 (122,'Anjali','Verma','anjali.verma@nsut.ac.in','9810000122','Faculty',4),
 (123,'Sameer','Khan','sameer.khan@nsut.ac.in','9810000123','Faculty',4),
 -- Mechanical
 (131,'Harish','Nair','harish.nair@nsut.ac.in','9810000131','Faculty',5),
 (132,'Ritu','Chawla','ritu.chawla@nsut.ac.in','9810000132','Faculty',5),
 -- Mathematics
 (141,'Deepa','Bose','deepa.bose@nsut.ac.in','9810000141','Faculty',6),
 (142,'Amit','Saxena','amit.saxena@nsut.ac.in','9810000142','Faculty',6),
 -- Civil (West campus)
 (151,'Kunal','Joshi','kunal.joshi@nsut.ac.in','9810000151','Faculty',7),
 (152,'Shalini','Rawat','shalini.rawat@nsut.ac.in','9810000152','Faculty',7),
 -- Senior academic administrators (faculty attached to offices)
 (161,'Alok','Mishra','alok.mishra@nsut.ac.in','9810000161','Faculty',10),
 (162,'Kavita','Arora','kavita.arora@nsut.ac.in','9810000162','Faculty',15),
 (163,'Sanjay','Tiwari','sanjay.tiwari@nsut.ac.in','9810000163','Faculty',11),
 (164,'Nandini','Rao','nandini.rao@nsut.ac.in','9810000164','Faculty',17),
 (165,'Manoj','Pandey','manoj.pandey@nsut.ac.in','9810000165','Faculty',5),
 (166,'Rohit','Agarwal','rohit.agarwal@nsut.ac.in','9810000166','Faculty',4),
 (167,'Sneha','Bhatt','sneha.bhatt@nsut.ac.in','9810000167','Faculty',3),
 (168,'Priya','Menon','priya.menon@nsut.ac.in','9810000168','Faculty',6),
 (169,'Varun','Dixit','varun.dixit@nsut.ac.in','9810000169','Faculty',7),
 (170,'Raghav','Menon','raghav.menon@nsut.ac.in','9810000170','Faculty',1),
 (171,'Ashok','Kulkarni','ashok.kulkarni@nsut.ac.in','9810000171','Faculty',18),
 (172,'Mohan','Lal','mohan.lal@nsut.ac.in','9810000172','Staff',1),          -- Ombudsperson (retired judge)
 -- Non-teaching staff
 (201,'Ramesh','Yadav','ramesh.yadav@nsut.ac.in','9810000201','Staff',20),
 (202,'Suresh','Pal','suresh.pal@nsut.ac.in','9810000202','Staff',21),
 (203,'Dinesh','Kumar','dinesh.kumar@nsut.ac.in','9810000203','Staff',22),
 (204,'Sunita','Devi','sunita.devi@nsut.ac.in','9810000204','Staff',23),
 (205,'Gopal','Singh','gopal.singh@nsut.ac.in','9810000205','Staff',24),
 (206,'Anil','Sharma','anil.sharma@nsut.ac.in','9810000206','Staff',12),
 (207,'Rekha','Jain','rekha.jain@nsut.ac.in','9810000207','Staff',13),
 (208,'Prakash','Rao','prakash.rao@nsut.ac.in','9810000208','Staff',13),
 (209,'Vinod','Bansal','vinod.bansal@nsut.ac.in','9810000209','Staff',14),
 (210,'Pallavi','Gupta','pallavi.gupta@nsut.ac.in','9810000210','Staff',16),
 (211,'Mukesh','Arora','mukesh.arora@nsut.ac.in','9810000211','Staff',2),
 (212,'Seema','Joshi','seema.joshi@nsut.ac.in','9810000212','Staff',3),
 (213,'Rakesh','Mehra','rakesh.mehra@nsut.ac.in','9810000213','Staff',4),
 (214,'Usha','Rani','usha.rani@nsut.ac.in','9810000214','Staff',5),
 (215,'Naveen','Chopra','naveen.chopra@nsut.ac.in','9810000215','Staff',6),
 (216,'Kiran','Bedi','kiran.bedi@nsut.ac.in','9810000216','Staff',7);

INSERT INTO faculty (person_id, employee_code, designation)
SELECT person_id,
       'NSUT-F' || person_id,
       CASE
         WHEN person_id IN (102,111,121,131,141,151,161,162,163,164,170,171) THEN 'Professor'
         WHEN person_id IN (101,103,112,122,132,142,152) THEN 'Associate Professor'
         ELSE 'Assistant Professor'
       END
FROM person
WHERE person_type = 'Faculty';

-- ---------------------------------------------------------------------
-- Positions and the reporting hierarchy  (reports_to = superior post)
-- ---------------------------------------------------------------------
INSERT INTO position (position_id, title, role_code, unit_id, holder_id, reports_to) VALUES
 -- top of the hierarchy
 (1,  'Vice Chancellor',                 'ViceChancellor',    NULL, 170, NULL),
 (2,  'Registrar',                       'Registrar',         14,   209, 1),
 (3,  'Dean Academics',                  'DeanAcademics',     10,   161, 1),
 (4,  'Dean Student Welfare',            'DeanStudentWelfare',15,   162, 1),
 (5,  'Controller of Examinations',      'CoE',               11,   163, 3),
 (6,  'Chief Warden',                    'ChiefWarden',       17,   164, 4),
 (7,  'Proctor',                         'Proctor',           18,   171, 4),
 (8,  'Grievance Triage Officer',        'TriageOfficer',     16,   210, 4),
 (9,  'Head, Computer Centre',           'ComputerCentreHead',13,   208, 2),
 (10, 'Computer Centre Helpdesk',        'ComputerCentreStaff',13,  207, 9),
 -- hostels : Caretaker -> Warden -> Chief Warden
 (20, 'Warden BH-1',                     'Warden',            20,   165, 6),
 (21, 'Warden BH-2',                     'Warden',            21,   166, 6),
 (22, 'Warden BH-3',                     'Warden',            22,   167, 6),
 (23, 'Warden GH-1',                     'Warden',            23,   168, 6),
 (24, 'Warden West Campus Hostel',       'Warden',            24,   169, 6),
 (30, 'Caretaker BH-1',                  'Caretaker',         20,   201, 20),
 (31, 'Caretaker BH-2',                  'Caretaker',         21,   202, 21),
 (32, 'Caretaker BH-3',                  'Caretaker',         22,   203, 22),
 (33, 'Caretaker GH-1',                  'Caretaker',         23,   204, 23),
 (34, 'Caretaker West Campus Hostel',    'Caretaker',         24,   205, 24),
 -- academic departments : HOD -> Dean Academics
 (40, 'HOD CSE',                         'HOD',               2,    102, 3),
 (41, 'HOD IT',                          'HOD',               3,    111, 3),
 (42, 'HOD ECE',                         'HOD',               4,    121, 3),
 (43, 'HOD Mechanical',                  'HOD',               5,    131, 3),
 (44, 'HOD Mathematics',                 'HOD',               6,    141, 3),
 (45, 'HOD Civil',                       'HOD',               7,    151, 3),
 -- department admin officers -> HOD
 (50, 'Department Admin CSE',            'DeptAdmin',         2,    211, 40),
 (51, 'Department Admin IT',             'DeptAdmin',         3,    212, 41),
 (52, 'Department Admin ECE',            'DeptAdmin',         4,    213, 42),
 (53, 'Department Admin Mechanical',     'DeptAdmin',         5,    214, 43),
 (54, 'Department Admin Mathematics',    'DeptAdmin',         6,    215, 44),
 (55, 'Department Admin Civil',          'DeptAdmin',         7,    216, 45),
 -- Estate officer for each academic block -> that department's admin -> HOD
 (60, 'Estate Officer (CSE Block)',      'EstateOfficer',     2,    206, 50),
 (61, 'Estate Officer (IT Block)',       'EstateOfficer',     3,    206, 51),
 (62, 'Estate Officer (ECE Block)',      'EstateOfficer',     4,    206, 52),
 (63, 'Estate Officer (Mechanical Block)','EstateOfficer',    5,    206, 53),
 (64, 'Estate Officer (Mathematics Block)','EstateOfficer',   6,    206, 54),
 (65, 'Estate Officer (Civil Block)',    'EstateOfficer',     7,    206, 55),
 -- Lab in-charge -> HOD
 (70, 'Lab In-charge CSE',               'LabInCharge',       2,    105, 40),
 (71, 'Lab In-charge IT',                'LabInCharge',       3,    113, 41),
 (72, 'Lab In-charge ECE',               'LabInCharge',       4,    123, 42),
 -- Timetable coordinator -> HOD
 (80, 'Timetable Coordinator CSE',       'TimetableCoordinator', 2, 104, 40),
 (81, 'Timetable Coordinator IT',        'TimetableCoordinator', 3, 113, 41),
 (82, 'Timetable Coordinator ECE',       'TimetableCoordinator', 4, 122, 42);

-- ---------------------------------------------------------------------
-- Committees and members
-- (UGC 2023 rules: SGRC chair + 4 members incl. a woman and an SC/ST/OBC
--  member, plus one student special invitee)
-- ---------------------------------------------------------------------
INSERT INTO committee (committee_id, name, committee_type, quorum) VALUES
 (1, 'Internal Complaints Committee',           'ICC',          3),
 (2, 'Anti-Ragging Committee',                  'AntiRagging',  3),
 (3, 'Student Grievance Redressal Committee',   'SGRC',         3),
 (4, 'Ombudsperson',                            'Ombudsperson', 1);
-- student invitees are added in 07_seed_demo.sql (students are created there)

INSERT INTO committee_member (committee_id, person_id, member_role, term_start, term_end) VALUES
 (1, 141, 'Chair',  '2025-07-01', '2027-06-30'),   -- ICC
 (1, 122, 'Member', '2025-07-01', '2027-06-30'),
 (1, 103, 'Member', '2025-07-01', '2027-06-30'),   -- CSE: recused when respondent is from CSE
 (1, 132, 'Member', '2025-07-01', '2027-06-30'),
 (2, 171, 'Chair',  '2025-07-01', '2027-06-30'),   -- Anti-Ragging (Proctor chairs)
 (2, 169, 'Member', '2025-07-01', '2027-06-30'),
 (2, 112, 'Member', '2025-07-01', '2027-06-30'),
 (2, 165, 'Member', '2025-07-01', '2027-06-30'),
 (3, 131, 'Chair',  '2025-07-01', '2027-06-30'),   -- SGRC
 (3, 152, 'Member', '2025-07-01', '2027-06-30'),
 (3, 142, 'Member', '2025-07-01', '2027-06-30'),
 (3, 111, 'Member', '2025-07-01', '2027-06-30'),
 (3, 104, 'Member', '2025-07-01', '2027-06-30'),   -- CSE: recused when respondent is from CSE
 (4, 172, 'Chair',  '2025-07-01', '2028-06-30');   -- Ombudsperson

-- ---------------------------------------------------------------------
-- Complaint categories (domain, sensitivity, base priority, SLA)
-- ---------------------------------------------------------------------
INSERT INTO category (category_id, name, domain, sensitivity, base_priority, sla_hours, anonymous_allowed, appeal_window_days) VALUES
 (1,  'Hostel - Water supply',                 'Hostel',         'Normal',    'Medium', 24,  FALSE, 15),
 (2,  'Hostel - Electricity',                  'Hostel',         'Normal',    'Medium', 24,  FALSE, 15),
 (3,  'Hostel - Cleaning and furniture',       'Hostel',         'Normal',    'Low',    72,  FALSE, 15),
 (4,  'Mess - Food quality and hygiene',       'Mess',           'Normal',    'Medium', 48,  TRUE,  15),
 (5,  'Building infrastructure',               'Infrastructure', 'Normal',    'Low',    72,  FALSE, 15),
 (6,  'Lab equipment',                         'LabEquipment',   'Normal',    'Medium', 48,  FALSE, 15),
 (7,  'Academic - Timetable clash',            'Academic',       'Normal',    'Medium', 72,  FALSE, 15),
 (8,  'Academic - Internal marks / attendance','Academic',       'Normal',    'Medium', 120, FALSE, 15),
 (9,  'Exam - Re-evaluation / result error',   'Exam',           'Normal',    'Medium', 168, FALSE, 15),
 (10, 'Wi-Fi / IT / IMS portal',               'IT',             'Normal',    'Low',    48,  FALSE, 15),
 (11, 'Faculty conduct',                       'FacultyConduct', 'Sensitive', 'High',   168, TRUE,  30),
 (12, 'Sexual harassment',                     'Harassment',     'Sensitive', 'High',   240, TRUE,  90),
 (13, 'Ragging',                               'Ragging',        'Sensitive', 'High',   24,  TRUE,  30),
 (14, 'Discrimination',                        'Discrimination', 'Sensitive', 'High',   168, TRUE,  30),
 (15, 'General / Other',                       'General',        'Normal',    NULL,     NULL, TRUE, 15);

-- ---------------------------------------------------------------------
-- CategoryRequirement : what each complaint type needs.
-- Sensitive categories: only respondent_role is mandatory ("not sure"
-- counts), so a sensitive complaint is never blocked.
-- ---------------------------------------------------------------------
INSERT INTO category_requirement (category_id, field_name, is_mandatory, question_prompt) VALUES
 (1, 'hostel',        TRUE,  'Which hostel is this in?'),
 (1, 'room_or_floor', TRUE,  'Which floor or room is affected?'),
 (1, 'since_when',    FALSE, 'Since when has this been happening?'),
 (2, 'hostel',        TRUE,  'Which hostel is this in?'),
 (2, 'room_or_floor', TRUE,  'Which floor or room is affected?'),
 (2, 'since_when',    FALSE, 'Since when has this been happening?'),
 (3, 'hostel',        TRUE,  'Which hostel is this in?'),
 (3, 'room_or_floor', TRUE,  'Which floor or room is affected?'),
 (4, 'hostel',        TRUE,  'Which hostel mess is this about?'),
 (4, 'meal',          TRUE,  'Which meal or dish was the problem?'),
 (4, 'meal_date',     FALSE, 'On which day did this happen?'),
 (5, 'building_room', TRUE,  'Which building and room number?'),
 (5, 'item',          FALSE, 'What exactly is broken (AC, lights, fan, furniture...)?'),
 (6, 'lab_name',      TRUE,  'Which lab is this in?'),
 (6, 'equipment',     TRUE,  'Which equipment is not working?'),
 (7, 'course',        TRUE,  'Which course(s) clash?'),
 (7, 'clash_details', TRUE,  'Which day and time slot is the clash?'),
 (8, 'course',        TRUE,  'Which course is this about?'),
 (8, 'assessment',    FALSE, 'Which assessment or attendance record?'),
 (9, 'course',        TRUE,  'Which course is this about?'),
 (9, 'exam',          TRUE,  'Mid-semester or end-semester exam?'),
 (9, 'question_numbers', TRUE, 'Which question numbers do you want re-checked?'),
 (10,'device_or_service', TRUE, 'Which service is affected (Wi-Fi, IMS portal, lab PC...)?'),
 (10,'location',      FALSE, 'Where are you facing the problem?'),
 (11,'respondent_role', TRUE, 'Is the person a faculty member, staff, or are you not sure?'),
 (11,'respondent_identity', FALSE, 'Can you tell us who this is? Choose from suggestions or describe them.'),
 (11,'incident_details', FALSE, 'If you are comfortable, describe what happened.'),
 (12,'respondent_role', TRUE, 'Is the person a student, faculty member, staff, or are you not sure?'),
 (12,'respondent_identity', FALSE, 'Can you tell us who this is? Choose from suggestions or describe them.'),
 (12,'incident_details', FALSE, 'If you are comfortable, describe what happened.'),
 (12,'incident_date', FALSE, 'Roughly when did it happen?'),
 (12,'witnesses',     FALSE, 'Did anyone else see it? (optional)'),
 (13,'respondent_role', TRUE, 'Are the people involved students, or are you not sure?'),
 (13,'location',      FALSE, 'Where did it happen? (optional)'),
 (13,'incident_date', FALSE, 'Roughly when did it happen? (optional)'),
 (14,'respondent_role', TRUE, 'Is the person a student, faculty member, staff, or are you not sure?'),
 (14,'incident_details', FALSE, 'If you are comfortable, describe what happened.');

-- ---------------------------------------------------------------------
-- RoutingRule : category -> first handler (role or committee)
-- ---------------------------------------------------------------------
INSERT INTO routing_rule (rule_id, category_id, target_role_code, target_committee_id, priority) VALUES
 (1,  1,  'Caretaker',            NULL, 1),
 (2,  2,  'Caretaker',            NULL, 1),
 (3,  3,  'Caretaker',            NULL, 1),
 (4,  4,  'Warden',               NULL, 1),
 (5,  5,  'EstateOfficer',        NULL, 1),
 (6,  6,  'LabInCharge',          NULL, 1),
 (7,  7,  'TimetableCoordinator', NULL, 1),
 (8,  8,  'HOD',                  NULL, 1),
 (9,  9,  'CoE',                  NULL, 1),
 (10, 10, 'ComputerCentreStaff',  NULL, 1),
 (11, 11, NULL,                   3,    1),   -- SGRC
 (12, 12, NULL,                   1,    1),   -- ICC
 (13, 13, NULL,                   2,    1),   -- Anti-Ragging Committee
 (14, 14, NULL,                   3,    1),   -- SGRC
 (15, 15, 'TriageOfficer',        NULL, 1);

-- keep identity counters ahead of the explicit ids used above
SELECT setval(pg_get_serial_sequence('sunwai.department','unit_id'),   100);
SELECT setval(pg_get_serial_sequence('sunwai.person','person_id'),     1000);
SELECT setval(pg_get_serial_sequence('sunwai.position','position_id'), 100);
SELECT setval(pg_get_serial_sequence('sunwai.committee','committee_id'), 10);
SELECT setval(pg_get_serial_sequence('sunwai.category','category_id'), 100);
SELECT setval(pg_get_serial_sequence('sunwai.routing_rule','rule_id'), 100);
