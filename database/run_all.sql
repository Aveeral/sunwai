-- =====================================================================
--  run_all.sql : builds the whole Sunwai database from scratch.
--  Usage:  psql "<connection string>" -v ON_ERROR_STOP=1 -f run_all.sql
--  (run it from inside the database/ folder)
-- =====================================================================
\set ON_ERROR_STOP on
-- password for the sunwai_app login (override with -v app_password=...)
\if :{?app_password}
\else
  \set app_password sunwai_app_dev
\endif
\echo '1/8 schema (28 tables)'
\i 01_schema.sql
\echo '2/8 reference data (NSUT structure, categories, rules)'
\i 02_seed_reference.sql
\echo '3/8 helper functions'
\i 03_functions.sql
\echo '4/8 triggers'
\i 04_triggers.sql
\echo '5/8 procedures (routing, conflict check, escalation, completeness ...)'
\i 05_procedures.sql
\echo '6/8 views'
\i 06_views.sql
\echo '7/8 security (roles, GRANT/REVOKE, row-level security)'
\i 07_security.sql
\echo '8/8 demo data (students, exams, ~60 complaints)'
\i 08_seed_demo.sql
\echo 'Done.'
