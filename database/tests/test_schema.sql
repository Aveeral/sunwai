-- Schema: 28 tables exist; constraints reject bad data.
\echo '--- test_schema ---'
BEGIN;
\i tests/00_test_helpers.sql

DO $$
DECLARE v_err text;
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM information_schema.tables
                      WHERE table_schema = 'sunwai' AND table_type = 'BASE TABLE') = 28,
                     'exactly 28 tables in the schema');

  PERFORM pg_temp.ok((SELECT count(*) FROM information_schema.table_constraints
                      WHERE table_schema = 'sunwai' AND constraint_type = 'PRIMARY KEY') = 28,
                     'every table has a primary key');

  -- composite keys of the weak entities
  PERFORM pg_temp.ok((SELECT count(*) FROM information_schema.key_column_usage k
                      JOIN information_schema.table_constraints t USING (constraint_name, table_schema, table_name)
                      WHERE t.constraint_type = 'PRIMARY KEY' AND k.table_schema = 'sunwai'
                        AND k.table_name IN ('status_history','clarification','question_dispute','category_requirement')) = 8,
                     'weak entities have (owner key + partial key) primary keys');

  BEGIN
    INSERT INTO complaint (description, visibility) VALUES ('test complaint', 'Secret');
    v_err := NULL;
  EXCEPTION WHEN check_violation THEN v_err := 'blocked';
  END;
  PERFORM pg_temp.ok(v_err = 'blocked', 'CHECK rejects an invalid visibility value');

  BEGIN
    INSERT INTO routing_rule (category_id, target_role_code, target_committee_id, priority)
    VALUES (1, 'Caretaker', 1, 9);
    v_err := NULL;
  EXCEPTION WHEN check_violation THEN v_err := 'blocked';
  END;
  PERFORM pg_temp.ok(v_err = 'blocked', 'a routing rule must have exactly one target');

  BEGIN
    INSERT INTO complaint_party (complaint_id, party_no, party_role) VALUES (1, 99, 'Respondent');
    v_err := NULL;
  EXCEPTION WHEN check_violation THEN v_err := 'blocked';
  END;
  PERFORM pg_temp.ok(v_err = 'blocked', 'a complaint party needs a person, a role or a description');

  BEGIN
    INSERT INTO person (first_name, last_name, email, person_type, unit_id)
    VALUES ('X', 'Y', 'ram.kumar@nsut.ac.in', 'Faculty', 2);
    v_err := NULL;
  EXCEPTION WHEN unique_violation THEN v_err := 'blocked';
  END;
  PERFORM pg_temp.ok(v_err = 'blocked', 'UNIQUE email enforced');

  BEGIN
    INSERT INTO complaint (description, unit_id) VALUES ('test complaint', 9999);
    v_err := NULL;
  EXCEPTION WHEN foreign_key_violation THEN v_err := 'blocked';
  END;
  PERFORM pg_temp.ok(v_err = 'blocked', 'FOREIGN KEY rejects an unknown department');
END $$;
ROLLBACK;
