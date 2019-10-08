----------------------------------------------------------------------
-- Federated Tables management functions
----------------------------------------------------------------------

-- Take a server_config jsonb and transform it to an input suitable
-- for _CDB_SetUp_User_PG_FDW_Server
CREATE OR REPLACE FUNCTION @extschema@.__cdb_credentials_to_user_mapping(input_config jsonb)
RETURNS jsonb
AS $$
DECLARE
    user_mapping jsonb;
BEGIN
    user_mapping := json_build_object('user_mapping',
        jsonb_build_object(
            'user', input_config->'credentials'->'username',
            'password', input_config->'credentials'->'password'
        )
    );
    RETURN (input_config - 'credentials')::jsonb || user_mapping;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;


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
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Server(server_alias text, server_config jsonb)
RETURNS void
AS $$
DECLARE
    final_config jsonb;
BEGIN
    final_config := @extschema@.__cdb_credentials_to_user_mapping(server_config);
    PERFORM cartodb._CDB_SetUp_User_PG_FDW_Server(server_alias, final_config::json);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
