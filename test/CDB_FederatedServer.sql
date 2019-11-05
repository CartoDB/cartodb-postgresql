-- Setup
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
SET SESSION AUTHORIZATION postgres;
CREATE EXTENSION postgres_fdw;
\set QUIET off

\echo "List empty servers shows nothing"
SELECT '1.1', cartodb.CDB_Federated_Server_List_Servers();

\echo "List non-existent server shows nothing"
SELECT '1.2', cartodb.CDB_Federated_Server_List_Servers(server := 'doesNotExist');

\echo "Create and list a server works"
SELECT '1.3', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "fdw_user",
        "password": "foobarino"
    }
}'::jsonb);
SELECT '1.4', cartodb.CDB_Federated_Server_List_Servers();

\echo "Create and list a second server works"
SELECT '2.1', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote2'::text, config := '{
    "server": {
        "dbname": "fdw_target",
        "host": "localhost",
        "port": @@PGPORT@@,
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    },
    "credentials": {
        "username": "fdw_user",
        "password": "foobarino"
    }
}'::jsonb);
SELECT '2.2', cartodb.CDB_Federated_Server_List_Servers();

\echo "List server by name works"
SELECT '2.3', cartodb.CDB_Federated_Server_List_Servers(server := 'myRemote');


\echo "Re-register a second server works"
SELECT '3.1', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote2'::text, config := '{
    "server": {
        "dbname": "fdw_target",
        "host": "localhost",
        "port": @@PGPORT@@,
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    },
    "credentials": {
        "username": "other_remote_user",
        "password": "foobarino"
    }
}'::jsonb);
SELECT '3.2', cartodb.CDB_Federated_Server_List_Servers();

\echo "Unregister server 1 works"
SELECT '4.1', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote'::text);
SELECT '4.2', cartodb.CDB_Federated_Server_List_Servers();

\echo "Unregistering a server that doesn't exist fails"
SELECT '5.1', cartodb.CDB_Federated_Server_Unregister(server := 'doesNotExist'::text);

\echo "Unregister the second server works"
SELECT '6.1', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote2'::text);
SELECT '6.2', cartodb.CDB_Federated_Server_List_Servers();

\echo "Create a server with NULL name fails"
SELECT '7.0', cartodb.CDB_Federated_Server_Register_PG(server := NULL::text, config := '{ "server": {}, "credentials" : {}}');
\echo "Create a server with NULL config fails"
SELECT '7.01', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := NULL::jsonb);
\echo "Create a server with empty config fails"
SELECT '7.1', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{}');
\echo "Create a server without credentials fails"
SELECT '7.2', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{
    "server": {
        "dbname": "fdw_target",
        "host": "localhost",
        "port": @@PGPORT@@,
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    }
}'::jsonb);
\echo "Create a server with empty credentials works"
SELECT '7.3', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{
    "server": {
        "dbname": "fdw_target",
        "host": "localhost",
        "port": @@PGPORT@@,
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    },
    "credentials": { }
}'::jsonb);
SELECT '7.4', cartodb.CDB_Federated_Server_List_Servers();
SELECT '7.5', cartodb.CDB_Federated_Server_Unregister(server := 'empty'::text);
\echo "Create a server without options fails"
SELECT '7.6', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{
    "credentials": {
        "username": "other_remote_user",
        "password": "foobarino"
    }
}'::jsonb);

\echo "Create a server with special characters works"
SELECT '8.1', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote" or''not'::text, config := '{
    "server": {
        "dbname": "fdw target",
        "host": "localhost",
        "port": @@PGPORT@@,
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    },
    "credentials": {
        "username": "fdw user",
        "password": "foo barino"
    }
}'::jsonb);
SELECT '8.2', cartodb.CDB_Federated_Server_List_Servers();
SELECT '8.3', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote" or''not'::text);

-- Test permissions
\set QUIET on

-- We create a username following the same steps as organization members
CREATE ROLE cdb_fs_tester LOGIN PASSWORD 'cdb_fs_passwd';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_fs_tester;
CREATE SCHEMA cdb_fs_tester AUTHORIZATION cdb_fs_tester;
SELECT cartodb.CDB_Organization_Create_Member('cdb_fs_tester');
ALTER ROLE cdb_fs_tester SET search_path TO cdb_fs_tester,cartodb,public;

\set QUIET off

SELECT '9.1', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote3'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "fdw_user",
        "password": "foobarino"
    }
}'::jsonb);

\c contrib_regression cdb_fs_tester

\echo "All users are able to list servers"
SELECT '9.2', cartodb.CDB_Federated_Server_List_Servers();

\echo "Only superadmins can create servers"
SELECT '9.3', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote4'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "fdw_user",
        "password": "foobarino"
    }
}'::jsonb);


\c contrib_regression postgres

\echo "Granting access to a user works"
SELECT '9.5', cartodb.CDB_Federated_Server_Grant_Access(server := 'myRemote3', usernames := ARRAY['cdb_fs_tester']);
SELECT '9.6', cartodb.CDB_Federated_Server_Grant_Access(server := 'does not exist', usernames := ARRAY['cdb_fs_tester']);
SELECT '9.7', cartodb.CDB_Federated_Server_Grant_Access(server := 'myRemote3', usernames := ARRAY['does not exist']);

\echo "Granting access again raises a notice"
SELECT '9.8', cartodb.CDB_Federated_Server_Grant_Access(server := 'myRemote3', usernames := ARRAY['cdb_fs_tester']);

\echo "Revoking access to a user works"
SELECT '9.9', cartodb.CDB_Federated_Server_Revoke_Access(server := 'myRemote3', usernames := ARRAY['cdb_fs_tester']);
SELECT '9.10', cartodb.CDB_Federated_Server_Grant_Access(server := 'myRemote3', usernames := ARRAY['cdb_fs_tester']);

\echo "Unregistering a server with active grants works"
SELECT '9.11', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote3'::text);


\echo "A user with granted access can't drop a server"
SELECT '10.1', cartodb.CDB_Federated_Server_Register_PG(server := 'myRemote4'::text, config := '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "fdw_user",
        "password": "foobarino"
    }
}'::jsonb);
SELECT '10.2', cartodb.CDB_Federated_Server_Grant_Access(server := 'myRemote4', usernames := ARRAY['cdb_fs_tester']);

\c contrib_regression cdb_fs_tester
SELECT '10.3', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote4'::text);

\c contrib_regression postgres
SELECT '10.4', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote4'::text);


-- Cleanup
\set QUIET on
DROP SCHEMA cdb_fs_tester CASCADE;
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester;
DROP ROLE cdb_fs_tester;
DROP EXTENSION postgres_fdw;
\set QUIET off
