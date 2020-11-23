-- Setup
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
SET SESSION AUTHORIZATION postgres;
\set QUIET off

\echo '## Setup'
CREATE TABLE testtable (stable integer, c1 integer, c2 integer, c3 integer, c4 integer);
INSERT INTO testtable(stable,c1,c2,c3,c4) VALUES (1,2,3,4,5), (2,3,4,5,6), (3,4,5,6,7);
\d+ testtable
SELECT * FROM testtable ORDER BY stable ASC;
SELECT 'testtable'::regclass::oid as id INTO temp table original_oid;

\echo '## Run cartodb.CDB_RegenerateTable and confirm the data and columns are the same'
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
\d+ testtable
SELECT * FROM testtable ORDER BY stable ASC;

\echo '## The table oid must have changed since the table itself changed'
SELECT 'testtable'::regclass::oid as id INTO temp table new_oid;
SELECT original_oid.id = new_oid.id FROM original_oid, new_oid;

\echo '## Check adding an index'
CREATE INDEX testtable_stable_idx ON testtable (stable NULLS FIRST) WITH (fillfactor = 80, vacuum_cleanup_index_scale_factor = 0.11);
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;


\echo '## Check column properties'
ALTER TABLE testtable ADD UNIQUE (c2);
ALTER TABLE testtable ALTER COLUMN c3 SET NOT NULL;
\d+ testtable
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;

SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
\d+ testtable
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;

\echo '## Check triggers'
CREATE OR REPLACE FUNCTION trigger_example_fn()
    RETURNS TRIGGER 
    LANGUAGE PLPGSQL
AS
$$
BEGIN
	RETURN NEW;
END;
$$;

CREATE TRIGGER testtable_trigger_example
    BEFORE UPDATE
    ON testtable
    FOR EACH ROW
    EXECUTE PROCEDURE trigger_example_fn();

SELECT event_object_schema as table_schema,
       event_object_table as table_name,
       trigger_schema,
       trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'testtable'
GROUP BY 1,2,3,4
ORDER BY table_schema,
         table_name;

SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);

SELECT event_object_schema as table_schema,
       event_object_table as table_name,
       trigger_schema,
       trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'testtable'
GROUP BY 1,2,3,4
ORDER BY table_schema,
         table_name,
         trigger_name;

\echo '## Check Cartodbfycation'
DROP INDEX testtable_stable_idx;
DROP TRIGGER testtable_trigger_example ON testtable;
SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := false);
SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := true);
SELECT CDB_SetUserQuotaInBytes(0);
SELECT CDB_CartodbfyTable('testtable'::regclass);
SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := false);
SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := true);
\d+ testtable
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;
SELECT event_object_schema as table_schema,
       event_object_table as table_name,
       trigger_schema,
       trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'testtable'
GROUP BY 1,2,3,4
ORDER BY table_schema,
         table_name,
         trigger_name;

SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);

SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := false);
SELECT cartodb.CDB_GetTableQueries('testtable'::regclass::oid, ignore_cartodbfication := true);

\d+ testtable
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE tablename = 'testtable' ORDER BY tablename, indexname;
SELECT event_object_schema as table_schema,
       event_object_table as table_name,
       trigger_schema,
       trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'testtable'
GROUP BY 1,2,3,4
ORDER BY table_schema,
         table_name,
         trigger_name;

\echo '## Test view / matview dependencies: It will not work but data will be the same'
CREATE VIEW testview AS SELECT * FROM testtable WHERE stable < 20;
SELECT * FROM testview ORDER BY stable ASC;
\d testtable

SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
DROP VIEW testview;
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);

CREATE MATERIALIZED VIEW testmatview AS SELECT * FROM testtable WHERE stable < 20;
SELECT * FROM testmatview ORDER BY stable ASC;
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
DROP MATERIALIZED VIEW testmatview;
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);

\d testtable

\echo '## Test role access'
CREATE ROLE cdb_regenerate_tester LOGIN PASSWORD 'cdb_regenerate_pass';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_regenerate_tester;
GRANT SELECT ON testtable TO cdb_regenerate_tester;
\c contrib_regression cdb_regenerate_tester
SELECT * FROM testtable ORDER BY cartodb_id DESC;
\c contrib_regression postgres

SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);

\c contrib_regression cdb_regenerate_tester
SELECT * FROM testtable ORDER BY cartodb_id DESC;
\c contrib_regression postgres

\echo '## Test calling with read only access (should fail)'
\c contrib_regression cdb_regenerate_tester
SELECT cartodb.CDB_RegenerateTable('testtable'::regclass::oid);
\c contrib_regression postgres

\echo '## Test partitioned table'
CREATE TABLE measurement (
    city_id         int not null,
    logdate         date not null,
    peaktemp        int,
    unitsales       int
) PARTITION BY RANGE (logdate);

CREATE TABLE measurement_y2006m02 PARTITION OF measurement
    FOR VALUES FROM ('2006-02-01') TO ('2006-03-01')
    PARTITION BY RANGE (peaktemp);

CREATE TABLE measurement_y2006m03 PARTITION OF measurement
    FOR VALUES FROM ('2006-03-01') TO ('2006-04-01');
CREATE INDEX ON measurement_y2006m02 (logdate);
CREATE INDEX ON measurement_y2006m03 (logdate);

\d measurement
SELECT  c.oid::pg_catalog.regclass,
        pg_catalog.pg_get_expr(c.relpartbound, c.oid),
        c.relkind
FROM pg_catalog.pg_class c,
     pg_catalog.pg_inherits i
WHERE c.oid=i.inhrelid AND i.inhparent = 'measurement'::regclass::oid
ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;
\d measurement_y2006m02
\d measurement_y2006m03

SELECT cartodb.CDB_RegenerateTable('measurement'::regclass::oid);
SELECT cartodb.CDB_RegenerateTable('measurement_y2006m02'::regclass::oid);
SELECT  c.oid::pg_catalog.regclass,
        pg_catalog.pg_get_expr(c.relpartbound, c.oid),
        c.relkind
FROM pg_catalog.pg_class c,
     pg_catalog.pg_inherits i
WHERE c.oid=i.inhrelid AND i.inhparent = 'measurement'::regclass::oid
ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;
\d measurement_y2006m02
\d measurement_y2006m03

SELECT cartodb.CDB_GetTableQueries('measurement'::regclass::oid, ignore_cartodbfication := false);

\echo '## teardown'

DROP TABLE measurement CASCADE;
DROP TABLE testtable CASCADE;
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_regenerate_tester;
DROP ROLE cdb_regenerate_tester;
