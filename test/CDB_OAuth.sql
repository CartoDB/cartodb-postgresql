-- Create user and enable OAuth event trigger
\set QUIET on
SET client_min_messages TO error;
CREATE ROLE "creator_role" LOGIN;
CREATE ROLE "ownership_role" LOGIN;
GRANT ALL ON SCHEMA cartodb TO "creator_role";
SELECT CDB_Conf_SetConf('api_keys_creator_role', '{"username": "creator_role", "permissions":[], "ownership_role_name": "ownership_role"}');
SET SESSION AUTHORIZATION "creator_role";
SET client_min_messages TO notice;
\set QUIET off

CREATE TABLE test(id INT);
INSERT INTO test VALUES(1);
SELECT * FROM test;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test2;

\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_EnableOAuthReassignTablesTrigger();
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

CREATE TABLE test2(id INT);
INSERT INTO test2 VALUES(1);
SELECT * FROM test2;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test2;

-- Cleanup
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_DisableOAuthReassignTablesTrigger();
DROP TABLE test;
DROP TABLE test2;
DROP ROLE "ownership_role";
REVOKE ALL ON SCHEMA cartodb FROM "creator_role";
DROP ROLE "creator_role";
DELETE FROM cdb_conf WHERE key = 'api_keys_creator_role';
\set QUIET off
