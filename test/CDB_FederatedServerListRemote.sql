-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
SET SESSION AUTHORIZATION postgres;
CREATE EXTENSION postgres_fdw;
CREATE ROLE cdb_fs_tester SUPERUSER LOGIN PASSWORD 'cdb_fs_passwd';
CREATE DATABASE cdb_fs_tester OWNER cdb_fs_tester;

SELECT 'C1', cartodb.CDB_Federated_Server_Register_PG(server := 'loopback'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "cdb_fs_passwd"
    }
}'::jsonb);

SELECT 'C2', cartodb.CDB_Federated_Server_Register_PG(server := 'loopback2'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "cdb_fs_passwd"
    }
}'::jsonb);

-- ===================================================================
-- create objects used through FDW loopback server
-- ===================================================================
\c cdb_fs_tester cdb_fs_tester

CREATE TYPE user_enum AS ENUM ('foo', 'bar', 'buz');
CREATE SCHEMA "S 1";
CREATE TABLE "S 1"."T 1" (
	"C 1" int NOT NULL,
	c2 int NOT NULL,
	c3 text,
	c4 timestamptz,
	c5 timestamp,
	c6 varchar(10),
	c7 char(10),
	c8 user_enum,
	CONSTRAINT t1_pkey PRIMARY KEY ("C 1")
);
CREATE TABLE "S 1"."T 2" (
	c1 int NOT NULL,
	c2 text,
	CONSTRAINT t2_pkey PRIMARY KEY (c1)
);
CREATE TABLE "S 1"."T 3" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	c3 text,
	CONSTRAINT t3_pkey PRIMARY KEY (c1)
);
CREATE TABLE "S 1"."T 4" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	c3 text,
	CONSTRAINT t4_pkey PRIMARY KEY (c1)
);

-- Disable autovacuum for these tables to avoid unexpected effects of that
ALTER TABLE "S 1"."T 1" SET (autovacuum_enabled = 'false');
ALTER TABLE "S 1"."T 2" SET (autovacuum_enabled = 'false');
ALTER TABLE "S 1"."T 3" SET (autovacuum_enabled = 'false');
ALTER TABLE "S 1"."T 4" SET (autovacuum_enabled = 'false');

\c contrib_regression postgres
SET client_min_messages TO notice;
\set VERBOSITY terse
\set QUIET off


-- ===================================================================
-- Test the listing functions
-- ===================================================================
\echo 'Test listing of remote schemas (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(remote_server => 'loopback');

\echo 'Test listing of remote tables (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(remote_server => 'loopback', remote_schema => 'S 1');

-- ===================================================================
-- Cleanup
-- ===================================================================
\set QUIET on

\c cdb_fs_tester cdb_fs_tester
DROP TABLE "S 1". "T 1";
DROP TABLE "S 1". "T 2";
DROP TABLE "S 1". "T 3";
DROP TABLE "S 1". "T 4";

DROP SCHEMA "S 1";
DROP TYPE user_enum;

\c contrib_regression postgres
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse

SELECT 'D1', cartodb.CDB_Federated_Server_Unregister(server := 'loopback'::text);
SELECT 'D2', cartodb.CDB_Federated_Server_Unregister(server := 'loopback2'::text);
DROP DATABASE cdb_fs_tester;
DROP ROLE cdb_fs_tester;
\set QUIET off
