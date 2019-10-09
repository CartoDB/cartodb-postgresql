----------------------------------------------------------------------
-- Federated Tables management functions
----------------------------------------------------------------------

-- Take a config jsonb and transform it to an input suitable for
-- _CDB_SetUp_User_PG_FDW_Server
CREATE OR REPLACE FUNCTION @extschema@.__ft_credentials_to_user_mapping(input_config jsonb)
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


-- Take a config jsonb as input and return it augmented with default
-- options
CREATE OR REPLACE FUNCTION @extschema@.__ft_add_default_options(input_config jsonb)
RETURNS jsonb
AS $$
DECLARE
    default_options jsonb := '{
        "extensions": "postgis",
        "updatable": "false",
        "use_remote_estimate": "true",
        "fetch_size": "1000"
    }';
    server_config jsonb;
BEGIN
    server_config := default_options || to_jsonb(input_config->'server');
    RETURN jsonb_set(input_config, '{server}'::text[], server_config);
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;


--
-- Set up a federated server for later connection of tables/views
--
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
    final_config := @extschema@.__ft_credentials_to_user_mapping(
        @extschema@.__ft_add_default_options(server_config)
    );
    PERFORM cartodb._CDB_SetUp_User_PG_FDW_Server(server_alias, final_config::json);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- Set up a federated table
--
-- E.g:
-- SELECT cartodb.CDB_SetUp_PG_Federated_Table(
--   'amazon',                  -- mandatory, name of the federated server
--   'my_remote_schema',        -- mandatory, schema name
--   'my_remote_table',         -- mandatory, table name
--   'id',                      -- mandatory, name of the id column
--   'geom',                    -- optional, name of the geom column, preferably in 4326
--   'webmercator_column_name', -- optional, must be in 3857 if present
-- );
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Table(
    server_alias text,
    schema_name name,
    table_name name,
    id_column name,
    geom_column_name name,
    webmercator_column_name name
)
RETURNS void
AS $$
DECLARE
    fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(server_alias);
    src_table REGCLASS;
BEGIN
    -- Import the foreign table
    PERFORM CDB_SetUp_User_PG_FDW_Table(server_alias, schema_name, table_name);

    -- Check id_column is numeric
    src_table := format('%s.%s', fdw_objects_name, table_name);
    PERFORM atttypid FROM pg_catalog.pg_attribute
       WHERE attrelid = src_table
         AND attname = id_column
         AND atttypid IN (SELECT oid FROM pg_type
           WHERE typname IN
             ('smallint', 'integer', 'bigint', 'int2', 'int4', 'int8'));
    IF NOT FOUND THEN
      RAISE EXCEPTION 'non integer id_column "%"', id_column;
    END IF;

    -- Create the view
    EXECUTE format(
        'CREATE OR REPLACE VIEW %1$I AS SELECT * FROM %2$I.%1$s',
        table_name,
        fdw_objects_name
    );

    -- Grant perms to the view
    EXECUTE format('GRANT SELECT ON %I TO %s', table_name, fdw_objects_name);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
