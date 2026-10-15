-- DCL and row-level security. Each check switches to a real database role
-- (SET LOCAL ROLE) exactly like the backend does, so every "permission
-- denied" below comes from PostgreSQL itself.
\echo '--- test_security ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE
  v_icc int; v_rag int; v_water int; v_wifi int; v_mine int; v_seen int; v_other int;
  v_err text; v_n int; v_logs int;
BEGIN
  -- the showcase complaints from the demo data
  SELECT c.complaint_id INTO v_icc FROM complaint c JOIN complainant_identity i USING (complaint_id)
   WHERE c.category_id = 12 AND i.person_id = 1002 ORDER BY c.complaint_id LIMIT 1;
  SELECT complaint_id INTO v_rag FROM complaint WHERE category_id = 13 ORDER BY complaint_id LIMIT 1;
  SELECT c.complaint_id INTO v_water FROM complaint c JOIN routing_decision d
      ON d.decision_id = latest_decision(c.complaint_id)
   WHERE c.category_id = 1 AND c.status = 'Assigned' AND d.assigned_person_id = 203 LIMIT 1;
  SELECT complaint_id INTO v_wifi FROM complaint WHERE category_id = 10 AND status = 'Assigned' LIMIT 1;
  SELECT count(*) INTO v_mine FROM complainant_identity WHERE person_id = 1002;

  -- 1. A student sees only their own complaints (row-level security)
  PERFORM pg_temp.act_as(1002);
  SET LOCAL ROLE sunwai_student;
  SELECT count(*) INTO v_seen FROM complaint;
  RESET ROLE;
  PERFORM pg_temp.ok(v_seen = v_mine, format('student sees only her own %s complaints (RLS)', v_mine));

  PERFORM pg_temp.act_as(1001);
  SET LOCAL ROLE sunwai_student;
  SELECT count(*) INTO v_other FROM complaint WHERE complaint_id = v_icc;
  RESET ROLE;
  PERFORM pg_temp.ok(v_other = 0, 'another student cannot see Riya''s ICC complaint at all');

  -- 2. A student cannot open the ICC case view (no GRANT)
  PERFORM pg_temp.act_as(1002);
  BEGIN
    SET LOCAL ROLE sunwai_student;
    PERFORM count(*) FROM v_icc_cases;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for view v_icc_cases', 'student: permission denied for view v_icc_cases');

  -- 3. A student cannot edit a complaint's text, even their own (column privileges)
  BEGIN
    SET LOCAL ROLE sunwai_student;
    UPDATE complaint SET description = 'changed text' WHERE complaint_id = v_icc;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for table complaint', 'student: permission denied to change complaint text');

  -- 4. A student cannot run escalation or touch the history
  BEGIN
    SET LOCAL ROLE sunwai_student;
    PERFORM escalate_overdue();
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for function escalate_overdue', 'student: cannot execute escalate_overdue()');
  BEGIN
    SET LOCAL ROLE sunwai_student;
    DELETE FROM status_history;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for table status_history', 'student: cannot delete status history (REVOKE)');

  -- 5. Handler: may change ONLY the status columns, and only on their own cases
  PERFORM pg_temp.act_as(203);                     -- BH-3 caretaker
  SET LOCAL ROLE sunwai_handler;
  UPDATE complaint SET status = 'InProgress' WHERE complaint_id = v_water;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 1, 'handler can update the status of a complaint assigned to them');

  SET LOCAL ROLE sunwai_handler;
  UPDATE complaint SET status = 'InProgress' WHERE complaint_id = v_wifi;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 0, 'handler cannot touch a complaint assigned to someone else (0 rows, RLS)');

  BEGIN
    SET LOCAL ROLE sunwai_handler;
    UPDATE complaint SET description = 'rewritten by handler' WHERE complaint_id = v_water;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for table complaint',
                     'handler: permission denied to change the student''s text (column-level GRANT)');

  -- 6. ICC member sees the case; the recused member does not
  PERFORM pg_temp.act_as(141);
  SET LOCAL ROLE sunwai_icc;
  SELECT count(*) INTO v_n FROM v_icc_cases WHERE complaint_id = v_icc;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 1, 'ICC member sees the harassment case in v_icc_cases');

  PERFORM pg_temp.act_as(103);
  SET LOCAL ROLE sunwai_icc;
  SELECT count(*) INTO v_n FROM v_icc_cases WHERE complaint_id = v_icc;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 0, 'recused ICC member (same department as respondent) cannot see the case');

  -- 7. Identity: visible to the ICC (consent given) but hidden on an anonymous complaint
  PERFORM pg_temp.act_as(141);
  SET LOCAL ROLE sunwai_icc;
  SELECT count(*) INTO v_n FROM complainant_identity WHERE complaint_id = v_icc;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 1, 'ICC member can see who filed (complainant consented to contact)');

  PERFORM pg_temp.act_as(171);                     -- Anti-Ragging chair
  SET LOCAL ROLE sunwai_antiragging;
  SELECT count(*) INTO v_seen FROM complaint WHERE complaint_id = v_rag;
  SELECT count(*) INTO v_n FROM complainant_identity WHERE complaint_id = v_rag;
  RESET ROLE;
  PERFORM pg_temp.ok(v_seen = 1 AND v_n = 0,
                     'anonymous ragging complaint: committee sees the case but NOT who filed it');

  PERFORM pg_temp.act_as(1005);
  SET LOCAL ROLE sunwai_student;
  SELECT count(*) INTO v_n FROM complainant_identity WHERE complaint_id = v_rag;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 1, 'the anonymous complainant can still track their own complaint');

  -- 8. Every opening of a confidential case is logged; students cannot read the log
  SELECT count(*) INTO v_logs FROM access_log WHERE complaint_id = v_icc;
  PERFORM pg_temp.act_as(141);
  SET LOCAL ROLE sunwai_icc;
  PERFORM open_complaint(v_icc);
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT count(*) FROM access_log WHERE complaint_id = v_icc) = v_logs + 1
                     AND (SELECT accessed_by FROM access_log WHERE complaint_id = v_icc
                          ORDER BY log_id DESC LIMIT 1) = 141,
                     'opening a confidential complaint writes an AccessLog row');
  PERFORM pg_temp.act_as(1001);
  BEGIN
    SET LOCAL ROLE sunwai_student;
    PERFORM open_complaint(v_icc);
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for complaint%', 'a stranger cannot open the case');
  BEGIN
    SET LOCAL ROLE sunwai_student;
    PERFORM count(*) FROM access_log;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for table access_log', 'student: permission denied for the access log');

  -- 9. Administrator: aggregates and non-sensitive cases only; never identities
  PERFORM pg_temp.act_as(209);
  SET LOCAL ROLE sunwai_admin;
  SELECT count(*) INTO v_n FROM complaint c JOIN category cat USING (category_id)
   WHERE cat.sensitivity = 'Sensitive';
  SELECT total_complaints INTO v_seen FROM v_dashboard_summary;
  RESET ROLE;
  PERFORM pg_temp.ok(v_n = 0, 'administrator cannot see any sensitive complaint');
  PERFORM pg_temp.ok(v_seen = (SELECT count(*) FROM complaint), 'administrator dashboard shows totals for all complaints');
  BEGIN
    SET LOCAL ROLE sunwai_admin;
    PERFORM count(*) FROM complainant_identity;
    v_err := NULL;
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM pg_temp.ok(v_err LIKE 'permission denied for table complainant_identity',
                     'administrator: permission denied for complainant identities');
END $$;
ROLLBACK;
