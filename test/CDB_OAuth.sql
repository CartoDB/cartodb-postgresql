-- Create user and enable OAuth event trigger
\set QUIET on
SET client_min_messages TO error;
DROP ROLE IF EXISTS "creator_role";
CREATE ROLE "creator_role" LOGIN;
DROP ROLE IF EXISTS "ownership_role";
CREATE ROLE "ownership_role" LOGIN;
GRANT ALL ON SCHEMA cartodb TO "creator_role";
SELECT CDB_Conf_SetConf('api_keys_creator_role', '{"username": "creator_role", "permissions":[]}');
SET SESSION AUTHORIZATION "creator_role";
SET client_min_messages TO notice;
\set QUIET off

-- First part without event trigger

CREATE TABLE test(id INT);
INSERT INTO test VALUES(1);
CREATE TABLE test_tablesas AS SELECT * FROM test;
CREATE VIEW test_view AS SELECT * FROM test;
CREATE MATERIALIZED VIEW test_mview AS SELECT * FROM test;
SELECT * INTO test_selectinto FROM test;

SELECT * FROM test;
SELECT * FROM test_tablesas;
SELECT * FROM test_view;
SELECT * FROM test_mview;
SELECT * FROM test_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test;
SELECT * FROM test_tablesas;
SELECT * FROM test_view;
SELECT * FROM test_mview;
SELECT * FROM test_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

DROP TABLE test_tablesas;
DROP VIEW test_view;
DROP MATERIALIZED VIEW test_mview;
DROP TABLE test_selectinto;
DROP TABLE test;

-- Second part with event trigger but without ownership_role_name in cdb_conf

\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_EnableOAuthReassignTablesTrigger();
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

CREATE TABLE test2(id INT);
INSERT INTO test2 VALUES(1);
CREATE TABLE test2_tablesas AS SELECT * FROM test2;
CREATE VIEW test2_view AS SELECT * FROM test2;
CREATE MATERIALIZED VIEW test2_mview AS SELECT * FROM test2;
SELECT * INTO test2_selectinto FROM test2;

SELECT * FROM test2;
SELECT * FROM test2_tablesas;
SELECT * FROM test2_view;
SELECT * FROM test2_mview;
SELECT * FROM test2_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test2;
SELECT * FROM test2_tablesas;
SELECT * FROM test2_view;
SELECT * FROM test2_mview;
SELECT * FROM test2_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

DROP TABLE test2_tablesas;
DROP VIEW test2_view;
DROP MATERIALIZED VIEW test2_mview;
DROP TABLE test2_selectinto;
DROP TABLE test2;

-- Third part with event trigger but with empty ownership_role_name in cdb_conf

\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_Conf_SetConf('api_keys_creator_role', '{"username": "creator_role", "permissions":[], "ownership_role_name": ""}');
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

CREATE TABLE test3(id INT);
INSERT INTO test3 VALUES(1);
CREATE TABLE test3_tablesas AS SELECT * FROM test3;
CREATE VIEW test3_view AS SELECT * FROM test3;
CREATE MATERIALIZED VIEW test3_mview AS SELECT * FROM test3;
SELECT * INTO test3_selectinto FROM test3;

SELECT * FROM test3;
SELECT * FROM test3_tablesas;
SELECT * FROM test3_view;
SELECT * FROM test3_mview;
SELECT * FROM test3_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test3;
SELECT * FROM test3_tablesas;
SELECT * FROM test3_view;
SELECT * FROM test3_mview;
SELECT * FROM test3_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

DROP TABLE test3_tablesas;
DROP VIEW test3_view;
DROP MATERIALIZED VIEW test3_mview;
DROP TABLE test3_selectinto;
DROP TABLE test3;

-- Fourth part with the event trigger active and configured

\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_Conf_SetConf('api_keys_creator_role', '{"username": "creator_role", "permissions":[], "ownership_role_name": "ownership_role"}');
SET SESSION AUTHORIZATION "creator_role";
\set QUIET off

CREATE TABLE test4(id INT);
INSERT INTO test4 VALUES(1);
CREATE TABLE test4_tablesas AS SELECT * FROM test4;
CREATE VIEW test4_view AS SELECT * FROM test4;
CREATE MATERIALIZED VIEW test4_mview AS SELECT * FROM test4;
SELECT * INTO test4_selectinto FROM test4;

SELECT * FROM test4;
SELECT * FROM test4_tablesas;
SELECT * FROM test4_view;
SELECT * FROM test4_mview;
SELECT * FROM test4_selectinto;

\set QUIET on
SET SESSION AUTHORIZATION "ownership_role";
\set QUIET off

SELECT * FROM test4;
SELECT * FROM test4_tablesas;
SELECT * FROM test4_view;
SELECT * FROM test4_mview;
SELECT * FROM test4_selectinto;

-- Ownership role drops the tables
DROP TABLE test4_tablesas;
DROP VIEW test4_view;
DROP MATERIALIZED VIEW test4_mview;
DROP TABLE test4_selectinto;
DROP TABLE test4;

-- Cleanup
\set QUIET on
SET SESSION AUTHORIZATION postgres;
SELECT CDB_DisableOAuthReassignTablesTrigger();
DROP ROLE "ownership_role";
REVOKE ALL ON SCHEMA cartodb FROM "creator_role";
DROP ROLE "creator_role";
DELETE FROM cdb_conf WHERE key = 'api_keys_creator_role';
\set QUIET off
