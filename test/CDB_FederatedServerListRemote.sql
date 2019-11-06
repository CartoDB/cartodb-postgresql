-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
CREATE EXTENSION postgres_fdw;

CREATE ROLE cdb_fs_tester LOGIN PASSWORD 'cdb_fs_passwd';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_fs_tester;
CREATE ROLE cdb_fs_tester2 LOGIN PASSWORD 'cdb_fs_passwd2';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_fs_tester2;

-- Create database to be used as remote
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
-- Setup 1
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
-- Test listing remote schemas
-- ===================================================================
\echo '## Test listing of remote schemas without permissions before the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback');
\c contrib_regression postgres

\echo '## Test listing of remote schemas (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback');

\echo '## Test listing of remote schemas without permissions after the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback');
\c contrib_regression postgres

\echo '## Test listing of remote schemas with permissions (sunny day)'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback');
\c contrib_regression postgres

\echo '## Test listing of remote schemas without permissions after revoking access (rainy day)'
SELECT cartodb.CDB_Federated_Server_Revoke_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback');
\c contrib_regression postgres

\echo '## Test listing of remote schemas (rainy day): Server does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'Does Not Exist');


-- ===================================================================
-- Test listing remote tables
-- ===================================================================

\echo '## Test listing of remote tables without permissions before the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'S 1');
\c contrib_regression postgres

\echo '## Test listing of remote tables (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'S 1');

\echo '## Test listing of remote tables without permissions after the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'S 1');
\c contrib_regression postgres

\echo '## Test listing of remote tables with permissions (sunny day)'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'S 1');
\c contrib_regression postgres

\echo '## Test listing of remote tables without permissions after revoking access (rainy day)'
SELECT cartodb.CDB_Federated_Server_Revoke_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'S 1');
\c contrib_regression postgres

\echo '## Test listing of remote tables (rainy day): Server does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'Does Not Exist', remote_schema => 'S 1');

\echo '## Test listing of remote tables (rainy day): Remote schema does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback', remote_schema => 'Does Not Exist');


-- ===================================================================
-- Test listing remote columns
-- ===================================================================

\echo '## Test listing of remote columns without permissions before the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 1');
\c contrib_regression postgres

\echo '## Test listing of remote columns (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 1');

\echo '## Test listing of remote columns without permissions after the first instantiation (rainy day)'
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 1');
\c contrib_regression postgres

\echo '## Test listing of remote columns with permissions (sunny day)'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 1');
\c contrib_regression postgres

\echo '## Test listing of remote columns without permissions after revoking access (rainy day)'
SELECT cartodb.CDB_Federated_Server_Revoke_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 1');
\c contrib_regression postgres

\echo '## Test listing of remote columns (rainy day): Server does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'Does Not Exist', remote_schema => 'S 1', remote_table => 'T 1');

\echo '## Test listing of remote columns (rainy day): Remote schema does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'Does Not Exist', remote_table => 'T 1');

\echo '## Test listing of remote columns (rainy day): Remote table does not exist'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'Does Not Exist');

\echo '## Test listing of remote columns (rainy day): Remote table is NULL'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => NULL::text);


-- ===================================================================
-- Test that using a different user to list tables and dropping it
-- does not break the server: We use loopback2 as it's in a clean state
-- ===================================================================


\echo '## Test listing of remote objects with permissions (sunny day)'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback2', db_role := 'cdb_fs_tester2'::name);
\c contrib_regression cdb_fs_tester2
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback2');
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback2', remote_schema => 'S 1');
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback2', remote_schema => 'S 1', remote_table => 'T 1');

\c contrib_regression postgres
\echo '## Test that dropping the granted user works fine (sunny day)'
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester2;
DROP ROLE cdb_fs_tester2;

\echo '## Test listing of remote objects with other user still works (sunny day)'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback2', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback2');
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Tables(server => 'loopback2', remote_schema => 'S 1');
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback2', remote_schema => 'S 1', remote_table => 'T 1');


-- ===================================================================
-- Cleanup 1
-- ===================================================================
\set QUIET on

\c cdb_fs_tester cdb_fs_tester
DROP TABLE "S 1". "T 1";
DROP TABLE "S 1". "T 2";
DROP TABLE "S 1". "T 3";
DROP TABLE "S 1". "T 4";

DROP SCHEMA "S 1";
DROP TYPE user_enum;


-- ===================================================================
-- Setup 2: Using Postgis too
-- ===================================================================

\c cdb_fs_tester postgres

CREATE EXTENSION postgis;

\c cdb_fs_tester cdb_fs_tester

CREATE SCHEMA "S 1";
CREATE TABLE "S 1"."T 5" (
	geom       geometry(Geometry,4326),
	geom_wm    geometry(GeometryZ,3857),
	geo_nosrid geometry,
	geog       geography
);

\c contrib_regression postgres
SET client_min_messages TO notice;
\set VERBOSITY terse
\set QUIET off


-- ===================================================================
-- Test the listing functions
-- ===================================================================

\echo '## Test listing of remote geometry columns (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 5');
\echo '## Test listing of remote geometry columns (sunny day) - Rerun'
-- Rerun should be ok
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Columns(server => 'loopback', remote_schema => 'S 1', remote_table => 'T 5');


-- ===================================================================
-- Test invalid password
-- ===================================================================

\echo '## Check error message with invalid password (rainy day)'
SELECT cartodb.CDB_Federated_Server_Register_PG(server := 'loopback_invalid'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "wrong password"
    }
}'::jsonb);

SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(server => 'loopback_invalid');

SELECT cartodb.CDB_Federated_Server_Unregister(server := 'loopback_invalid'::text);

-- ===================================================================
-- Cleanup 2
-- ===================================================================
\set QUIET on

\c cdb_fs_tester cdb_fs_tester
DROP TABLE "S 1". "T 5";

DROP SCHEMA "S 1";

\c contrib_regression postgres
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse

SELECT 'D1', cartodb.CDB_Federated_Server_Unregister(server := 'loopback'::text);
SELECT 'D2', cartodb.CDB_Federated_Server_Unregister(server := 'loopback2'::text);

DROP DATABASE cdb_fs_tester;

-- Drop role
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester;
DROP ROLE cdb_fs_tester;

DROP EXTENSION postgres_fdw;

\set QUIET off
