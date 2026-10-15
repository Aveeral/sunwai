-- =====================================================================
--  run_tests.sql : runs every SQL test. Each test file rolls back, so the
--  database is unchanged afterwards. Look for PASS / FAIL lines.
--  Usage (from inside database/):
--    psql "<connection string>" -f run_tests.sql
-- =====================================================================
\set ON_ERROR_STOP off
\i tests/test_schema.sql
\i tests/test_routing.sql
\i tests/test_conflicts.sql
\i tests/test_workflow.sql
\i tests/test_reevaluation.sql
\i tests/test_security.sql
