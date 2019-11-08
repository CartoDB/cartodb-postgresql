-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
CREATE EXTENSION postgres_fdw;

CREATE ROLE cdb_fs_tester LOGIN PASSWORD 'cdb_fs_passwd';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_fs_tester;

-- Create database to be used as remote
CREATE DATABASE cdb_fs_tester OWNER cdb_fs_tester;

SELECT 'C1', cartodb.CDB_Federated_Server_Register_PG(server => 'loopback'::text, config => '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "cdb_fs_passwd"
    }
}'::jsonb);
\set QUIET off


-- ===================================================================
-- Test server diagnostics function(s)
-- ===================================================================
\echo '%% It raises an error if the server does not exist'
SELECT '1.1', cartodb.CDB_Federated_Server_Diagnostics(server => 'doesNotExist');

\echo '%% It returns a jsonb object'
SELECT '1.2', pg_typeof(cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback'));

\echo '%% It returns the server version'
SELECT '1.3', cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback') @> format('{"server_version": "%s"}', setting)::jsonb
    FROM pg_settings WHERE name = 'server_version';


-- ===================================================================
-- Cleanup
-- ===================================================================
\set QUIET on
SELECT 'D1', cartodb.CDB_Federated_Server_Unregister(server => 'loopback'::text);
-- Reconnect, using a new session in order to close FDW connections
\connect
DROP DATABASE cdb_fs_tester;

-- Drop role
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester;
DROP ROLE cdb_fs_tester;

DROP EXTENSION postgres_fdw;
\set QUIET off
