set client_min_messages to error;
\set VERBOSITY TERSE
-- Runs a query and returns whether an error was thrown
-- Useful when the error message depends on the execution plan or db settings
-- The error message outputs the extra quota, and this might depend on the database setup and version
CREATE OR REPLACE FUNCTION catch_error(query text)
RETURNS bool
AS $$
BEGIN
    EXECUTE query;
    RETURN FALSE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN TRUE;
END
$$ LANGUAGE 'plpgsql';

CREATE TABLE big(a int);
-- Try the legacy interface
-- See https://github.com/CartoDB/cartodb-postgresql/issues/13
CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON big
      EXECUTE PROCEDURE cartodb.CDB_CheckQuota(2, 1, 'public');
INSERT INTO big VALUES (1); -- allowed, check runs before
SELECT 'excess1', catch_error($$INSERT INTO big VALUES (2); $$); -- disallowed, quota exceeds before
SELECT cartodb.CDB_SetUserQuotaInBytes(0);
SELECT cartodb.CDB_CartodbfyTable('big');
-- Creating the trigger should fail as it was created by CDB_CartodbfyTable
CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON big
      EXECUTE PROCEDURE cartodb.CDB_CheckQuota(2, 1, 'public');
-- Drop the trigger and recreate it forcing a 100% checks
DROP TRIGGER test_quota ON big;
CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON big
      EXECUTE PROCEDURE cartodb.CDB_CheckQuota(2, 1, 'public');
INSERT INTO big SELECT generate_series(2049,4096);
INSERT INTO big SELECT generate_series(4097,6144);
INSERT INTO big SELECT generate_series(6145,8192);
-- Test for #108: https://github.com/CartoDB/cartodb-postgresql/issues/108
SELECT cartodb.CDB_UserDataSize() < 500000 AND cartodb.CDB_UserDataSize() > 0;
SELECT cartodb._CDB_total_relation_size('public', 'big') < 1000000;
SELECT cartodb._CDB_total_relation_size('public', 'nonexistent_table_name');
-- END Test for #108

SELECT cartodb.CDB_SetUserQuotaInBytes(2);
SELECT 'excess2', catch_error($$INSERT INTO big VALUES (8193);$$);
SELECT cartodb.CDB_SetUserQuotaInBytes(0);
INSERT INTO big VALUES (8194);
DROP TABLE big;


--analysis tables should be excluded from quota:
CREATE TABLE big(a int);
CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON big
      EXECUTE PROCEDURE cartodb.CDB_CheckQuota(2, 1, 'public');
SELECT cartodb.CDB_SetUserQuotaInBytes(1);
CREATE TABLE analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d4(id int);
INSERT INTO analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d4(id) VALUES (1),(2),(3),(4),(5);
INSERT INTO big VALUES (1); -- allowed, check runs before
DROP TABLE analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d4;
SELECT 'excess3', catch_error($$INSERT INTO big VALUES (3);$$); -- disallowed, quota exceeds before
DROP TABLE big;
SELECT CDB_SetUserQuotaInBytes(0);


set client_min_messages to NOTICE;
DROP FUNCTION catch_error(text);
DROP FUNCTION _CDB_UserQuotaInBytes();
