-- Create user and enable Ghost tables trigger
\set QUIET on
SET client_min_messages TO error;
SELECT CDB_EnableGhostTablesTrigger();
CREATE ROLE "fulano" LOGIN;
GRANT ALL ON SCHEMA cartodb TO "fulano";
GRANT SELECT ON cartodb.cdb_ddl_execution TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_Username() TO "fulano";
GRANT EXECUTE ON FUNCTION CDB_LinkGhostTables(text) TO "fulano";
SELECT cartodb.CDB_Conf_SetConf('api_keys_fulano', '{"username": "fulanito", "permissions":[]}');
DELETE FROM cdb_conf WHERE key = 'invalidation_service';
SET SESSION AUTHORIZATION "fulano";
SET client_min_messages TO notice;
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called (configuration not found)

-- Add TIS configuration
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT cartodb.CDB_Conf_SetConf('invalidation_service', '{"host": "fake-tis-host", "port": 3142}');
SET SESSION AUTHORIZATION "fulano";
\set QUIET off

SELECT CDB_LinkGhostTables(); -- _CDB_LinkGhostTables called

BEGIN;
SELECT to_regclass('cartodb.cdb_ddl_execution'); -- exists
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

SELECT to_regclass('cartodb.cdb_ddl_execution'); -- not exists
DROP TABLE tmp; -- _CDB_LinkGhostTables not called

-- Cleanup
\set QUIET on
SET SESSION AUTHORIZATION postgres;
REVOKE EXECUTE ON FUNCTION CDB_LinkGhostTables(text) FROM "fulano";
REVOKE EXECUTE ON FUNCTION CDB_Username() FROM "fulano";
REVOKE ALL ON SCHEMA cartodb FROM "fulano";
DROP ROLE "fulano";
DELETE FROM cdb_conf WHERE key = 'api_keys_fulano' OR key = 'invalidation_service';
\set QUIET off
