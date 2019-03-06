-- Create user and enable Ghost tables trigger
\set QUIET on
CREATE ROLE "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db" LOGIN;
CREATE SCHEMA fulano;
GRANT ALL ON SCHEMA fulano TO "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
GRANT USAGE ON SCHEMA cartodb TO "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
GRANT SELECT ON cartodb.cdb_ddl_execution TO "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
GRANT EXECUTE ON FUNCTION CDB_LinkGhostTables() TO "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
SELECT CDB_EnableGhostTablesTrigger();
SET SESSION AUTHORIZATION "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called

BEGIN;
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
CREATE TABLE fulano.tmp(id INT);
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 1
END; -- _CDB_LinkGhostTables called

-- Disable Ghost tables trigger
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_DisableGhostTablesTrigger();
DROP TABLE fulano.tmp;
SET SESSION AUTHORIZATION "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
\set QUIET off

BEGIN;
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
CREATE TABLE fulano.tmp(id INT);
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
END; -- _CDB_LinkGhostTables not called

-- Clean test stuff
\set QUIET on
SET SESSION AUTHORIZATION postgres;
DROP TABLE fulano.tmp;
REVOKE EXECUTE ON FUNCTION CDB_LinkGhostTables() FROM "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
REVOKE SELECT ON cartodb.cdb_ddl_execution FROM "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
REVOKE USAGE ON SCHEMA cartodb FROM "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
REVOKE ALL ON SCHEMA fulano FROM "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
DROP ROLE "cartodb_user_b621f453-75ee-438f-acc9-8c5303f3d658_db";
\set QUIET off
