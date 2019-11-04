-- Setup
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
SET SESSION AUTHORIZATION postgres;
CREATE EXTENSION postgres_fdw;
\set QUIET off

-- Register a new server
SELECT '1.1', cartodb.CDB_Federated_Server_List_Servers();
SELECT '1.2', cartodb.CDB_Federated_Server_List_Servers(server := 'doesNotExist');
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

-- Register a second server
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
-- Check that CDB_Federated_Server_List_Servers works with name
SELECT '2.3', cartodb.CDB_Federated_Server_List_Servers(server := 'myRemote');


-- Re-register the second server
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

-- Unregister #1
SELECT '4.1', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote'::text);
SELECT '4.2', cartodb.CDB_Federated_Server_List_Servers();

-- Unregister a server that doesn't exist
SELECT '5.1', cartodb.CDB_Federated_Server_Unregister(server := 'doesNotExist'::text);

-- Unregister #2
SELECT '6.1', cartodb.CDB_Federated_Server_Unregister(server := 'myRemote2'::text);
SELECT '6.2', cartodb.CDB_Federated_Server_List_Servers();

-- Test empty config
SELECT '7.1', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{}');
-- Test without passing credentials
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
-- Test with empty credentials
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
-- Test without without server options
SELECT '7.6', cartodb.CDB_Federated_Server_Register_PG(server := 'empty'::text, config := '{
    "credentials": {
        "username": "other_remote_user",
        "password": "foobarino"
    }
}'::jsonb);

-- Should work ok with special characters
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

-- Should throw when trying to unregistering a server that doesn't exists
SELECT '8.4', cartodb.CDB_Federated_Server_Unregister(server := 'Does not exist'::text);

-- Cleanup
\set QUIET on
DROP EXTENSION postgres_fdw;
\set QUIET off


