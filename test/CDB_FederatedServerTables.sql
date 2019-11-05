-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse

SET SESSION AUTHORIZATION postgres;
CREATE EXTENSION postgres_fdw;

-- We create a username following the same steps as organization members
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


-- ===================================================================
-- create objects used through FDW loopback server
-- ===================================================================

\c cdb_fs_tester postgres

CREATE EXTENSION postgis;

\c cdb_fs_tester cdb_fs_tester

CREATE SCHEMA remote_schema;
CREATE TABLE remote_schema.remote_geom(id int, another_field text, geom geometry(Geometry,4326));

INSERT INTO remote_schema.remote_geom VALUES (1, 'patata', 'SRID=4326;POINT(1 1)'::geometry);
INSERT INTO remote_schema.remote_geom VALUES (2, 'patata2', 'SRID=4326;POINT(2 2)'::geometry);

CREATE TABLE remote_schema.remote_geom2(id bigint, another_field text, geom geometry(Geometry,4326), geom_mercator geometry(Geometry,3857));

INSERT INTO remote_schema.remote_geom2 VALUES (3, 'patata', 'SRID=4326;POINT(3 3)'::geometry, 'SRID=3857;POINT(3 3)');

CREATE TABLE remote_schema.remote_other(id bigint, field text, field2 text);
INSERT INTO remote_schema.remote_other VALUES (1, 'delicious', 'potatoes');


-- ===================================================================
-- Test the listing functions
-- ===================================================================

\c contrib_regression postgres
SET client_min_messages TO error;
\set VERBOSITY terse
\set QUIET off

\echo '## Registering an existing table works'
SELECT 'R1', cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom'
    );

SELECT 'V1', pg_get_viewdef('remote_geom');
SELECT 'S1', cartodb_id, ST_AsText(the_geom), another_field FROM remote_geom;

Select 'list_remotes1', CDB_Federated_Server_List_Registered_Tables(
    server => 'loopback',
    remote_schema => 'remote_schema'
);

\echo '## Registering another existing table works'
SELECT 'R2', cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom2',
    id_column => 'id',
    geom_column => 'geom',
    webmercator_column => 'geom_mercator',
    local_name => 'myFullTable'
    );

SELECT 'V2', pg_get_viewdef('"myFullTable"');
SELECT 'S2', cartodb_id, ST_AsText(the_geom), another_field FROM "myFullTable";

Select 'list_remotes2', CDB_Federated_Server_List_Registered_Tables(
    server => 'loopback',
    remote_schema => 'remote_schema'
);


\echo '## Re-registering a table works'
SELECT 'R3', cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom2',
    id_column => 'id',
    geom_column => 'geom',
    local_name => 'different_name'
    );

-- The old view should dissapear
SELECT 'S3_old', cartodb_id, ST_AsText(the_geom), another_field FROM "myFullTable";
-- And the new appear
SELECT 'S3_new', cartodb_id, ST_AsText(the_geom), another_field FROM different_name;

\echo '## Unregistering works'
-- Deregistering the first table
SELECT 'U1', CDB_Federated_Table_Unregister(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom'
    );
-- Selecting from the created view should fail now
SELECT 'UCheck1', cartodb_id, ST_AsText(the_geom), another_field FROM remote_geom;

Select 'list_remotes3', CDB_Federated_Server_List_Registered_Tables(
    server => 'loopback',
    remote_schema => 'remote_schema'
);

-- ===================================================================
-- Test input
-- ===================================================================

\echo '## Registering a table: Invalid server fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'Does not exist',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: NULL server fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => NULL::text,
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: Invalid schema fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'Does not exist',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: NULL schema fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => NULL::text,
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: Invalid table fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'Does not exist',
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: NULL table fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => NULL::text,
    id_column => 'id',
    geom_column => 'geom'
    );

\echo '## Registering a table: Invalid id fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'Does not exist',
    geom_column => 'geom'
    );

\echo '## Registering a table: NULL id fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  NULL::text,
    geom_column => 'geom'
    );

\echo '## Registering a table: Invalid geom_column fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'Does not exists'
    );

\echo '## Registering a table: NULL geom_column is OK'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => NULL::text
    );
SELECT cartodb.CDB_Federated_Table_Unregister(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom'
    );

\echo '## Registering a table: Invalid webmercator_column fails'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column => 'id',
    geom_column => 'geom',
    webmercator_column => 'Does not exists'
    );

\echo '## Registering a table: NULL webmercator_column is OK'
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => 'geom',
    webmercator_column => NULL::text
    );
SELECT cartodb.CDB_Federated_Table_Unregister(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom'
    );

-- ===================================================================
-- Test conflicts
-- ===================================================================

\echo '## Target conflict is handled nicely: Table'
CREATE TABLE localtable (a integer);
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => 'geom',
    local_name => 'localtable');

\echo '## Target conflict is handled nicely: View'
CREATE VIEW localtable2 AS Select * from localtable;
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => 'geom',
    local_name => 'localtable2');

DROP VIEW localtable2;
DROP TABLE localtable;

-- ===================================================================
-- Test permissions
-- ===================================================================


\echo '## Registering tables does not work without permissions'
\c contrib_regression cdb_fs_tester
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => 'geom',
    local_name => 'localtable');

\echo '## Listing registered tables does not work without permissions'
Select CDB_Federated_Server_List_Registered_Tables(server => 'loopback', remote_schema => 'remote_schema');

\echo '## Registering tables works with granted permissions'
\c contrib_regression postgres
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);
\c contrib_regression cdb_fs_tester
SELECT cartodb.CDB_Federated_Table_Register(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom',
    id_column =>  'id',
    geom_column => 'geom',
    local_name => 'localtable');

\echo '## Listing registered tables works with granted permissions'
Select CDB_Federated_Server_List_Registered_Tables(server => 'loopback', remote_schema => 'remote_schema');

\echo '## Selecting from a registered table with granted permissions works'
Select cartodb_id, ST_AsText(the_geom) from localtable;

\echo '## Selecting from a registered table without permissions does not work'
\c contrib_regression cdb_fs_tester2
CREATE OR REPLACE FUNCTION catch_permission_error(query text)
RETURNS bool
AS $$
BEGIN
    EXECUTE query;
    RETURN FALSE;
EXCEPTION
    WHEN insufficient_privilege THEN
        RETURN TRUE;
    WHEN OTHERS THEN
        RAISE WARNING 'Exception %', sqlstate;
        RETURN FALSE;
END
$$ LANGUAGE 'plpgsql';
Select catch_permission_error($$SELECT cartodb_id, ST_AsText(the_geom) from localtable$$);
DROP FUNCTION catch_permission_error(text);

\echo '## Deleting a registered table without permissions does not work'
SELECT CDB_Federated_Table_Unregister(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom'
    );

\echo '## Only the owner can grant permissions over the server'
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester2'::name);

\echo '## Everything works for a different user when granted permissions'
\c contrib_regression postgres
SELECT cartodb.CDB_Federated_Server_Grant_Access(server := 'loopback', db_role := 'cdb_fs_tester2'::name);
\c contrib_regression cdb_fs_tester2
Select CDB_Federated_Server_List_Registered_Tables(server => 'loopback', remote_schema => 'remote_schema');
Select cartodb_id, ST_AsText(the_geom) from localtable;

\echo '## A different user can unregister a table'
SELECT CDB_Federated_Table_Unregister(
    server => 'loopback',
    remote_schema => 'remote_schema',
    remote_table => 'remote_geom'
    );
Select CDB_Federated_Server_List_Registered_Tables(server => 'loopback', remote_schema => 'remote_schema');

\echo '## Only the owner can revoke permissions over the server'
SELECT cartodb.CDB_Federated_Server_Revoke_Access(server := 'loopback', db_role := 'cdb_fs_tester'::name);

-- ===================================================================
-- Cleanup
-- ===================================================================

\set QUIET on
\c contrib_regression postgres
SET client_min_messages TO error;
\set VERBOSITY terse

REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester2;
DROP ROLE cdb_fs_tester2;

SELECT 'D1', cartodb.CDB_Federated_Server_Unregister(server := 'loopback'::text);
DROP DATABASE cdb_fs_tester;
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester;
DROP ROLE cdb_fs_tester;
DROP EXTENSION postgres_fdw;
\set QUIET off
