----------------------------------------------------------------------
-- Federated Tables management functions
----------------------------------------------------------------------


--
-- Set up a federated server for later connection of tables/views
-- E.g:
-- SELECT cartodb.CDB_SetUp_PG_Federated_Server('amazon', '{
--    "server": {
--      "dbname": "testdb",
--      "host": "myhostname.us-east-2.rds.amazonaws.com",
--      "port": "5432"
--    },
--    "credentials": {
--      "username": "read_only_user",
--      "password": "secret"
--    }
-- }');
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Server(server_alias text, config json)
RETURNS void
AS $$
BEGIN
    -- TODO
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
