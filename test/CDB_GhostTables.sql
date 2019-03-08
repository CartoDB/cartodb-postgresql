-- Create user and enable Ghost tables trigger
\set QUIET on
SET client_min_messages TO error;
CREATE ROLE "fulano" LOGIN;
GRANT ALL ON SCHEMA cartodb TO "fulano";
GRANT SELECT ON cartodb.cdb_ddl_execution TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_Username() TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_LinkGhostTables() TO "fulano";
SELECT CDB_EnableGhostTablesTrigger();
INSERT INTO cdb_conf (key, value) VALUES ('api_keys_fulano', '{"username": "fulanito", "permissions":[]}');
SET SESSION AUTHORIZATION "fulano";
SET client_min_messages TO notice;
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called

BEGIN;
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
CREATE TABLE tmp(id INT);
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 1
END; -- _CDB_LinkGhostTables called

-- Disable Ghost tables trigger
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_DisableGhostTablesTrigger();
SET SESSION AUTHORIZATION "fulano";
\set QUIET off

BEGIN;
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
DROP TABLE tmp;
SELECT COUNT(*) FROM cartodb.cdb_ddl_execution; -- 0
END; -- _CDB_LinkGhostTables not called

-- Clean up
\set QUIET on
SET SESSION AUTHORIZATION postgres;
REVOKE EXECUTE ON FUNCTION CDB_LinkGhostTables() FROM "fulano";
REVOKE EXECUTE ON FUNCTION CDB_Username() FROM "fulano";
REVOKE SELECT ON cartodb.cdb_ddl_execution FROM "fulano";
REVOKE ALL ON SCHEMA cartodb FROM "fulano";
DROP ROLE "fulano";
\set QUIET off
