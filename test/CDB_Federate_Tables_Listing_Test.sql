-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO warning;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER testserver1 FOREIGN DATA WRAPPER postgres_fdw;
DO $d$
    BEGIN
        EXECUTE $$CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw
            OPTIONS (dbname '$$||current_database()||$$',
                     port '$$||current_setting('port')||$$'
            )$$;
        EXECUTE $$CREATE SERVER loopback2 FOREIGN DATA WRAPPER postgres_fdw
            OPTIONS (dbname '$$||current_database()||$$',
                     port '$$||current_setting('port')||$$'
            )$$;
    END;
$d$;

CREATE USER MAPPING FOR CURRENT_USER SERVER loopback;
CREATE USER MAPPING FOR CURRENT_USER SERVER loopback2;

-- ===================================================================
-- create objects used through FDW loopback server
-- ===================================================================
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
\set QUIET off


-- ===================================================================
-- Test the listing functions
-- ===================================================================
\echo 'Test CDB_Federated_Server_List_Remote_Schemas (sunny day)'
SELECT * FROM cartodb.CDB_Federated_Server_List_Remote_Schemas(remote_server => 'loopback')
    WHERE remote_schema NOT LIKE 'pg_%' -- Exclude toast and temp schemas
    ORDER BY remote_schema;

-- ===================================================================
-- Cleanup
-- ===================================================================
\set QUIET on
DROP TABLE "S 1". "T 1";
DROP TABLE "S 1". "T 2";
DROP TABLE "S 1". "T 3";
DROP TABLE "S 1". "T 4";

DROP SCHEMA "S 1";
DROP TYPE user_enum;

DROP USER MAPPING FOR CURRENT_USER SERVER loopback;
DROP USER MAPPING FOR CURRENT_USER SERVER loopback2;

DROP SERVER loopback CASCADE;
DROP SERVER loopback2 CASCADE;
\set QUIET off
