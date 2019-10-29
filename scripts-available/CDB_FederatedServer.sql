
-- This function is just a placement to store and use the pattern for
-- foreign server names
-- Servers:     cdb_fs_$(server_name)
-- Schemas:     cdb_fs_schema_$(md5sum(server_name || remote_schema_name))
-- Owner role:  cdb_fs_$(md5sum(current_database() || server_name)
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Name_Pattern()
RETURNS TEXT
AS $$
    SELECT 'cdb_fs_'::text;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;


-- Produce a valid DB name for servers generated for the Federated Server
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Server_Name(input_name TEXT, check_existence BOOL)
RETURNS NAME
AS $$
DECLARE
    object_name text := format('%s%s', @extschema@.__CDB_FS_Name_Pattern(), input_name);
BEGIN
    -- We discard anything that would be truncated
    IF (char_length(object_name) < 64) THEN
        IF (check_existence AND (NOT EXISTS (SELECT * FROM pg_foreign_server WHERE srvname = object_name))) THEN
            RAISE EXCEPTION 'Server "%" does not exist', input_name;
        END IF;
        RETURN object_name::name;
    ELSE
        RAISE EXCEPTION 'Server name is too long to be used as identifier';
    END IF;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Extract_Server_Name(fdw_stored_name NAME)
RETURNS TEXT
AS $$
    SELECT right(fdw_stored_name,
            char_length(fdw_stored_name::TEXT) - char_length(@extschema@.__CDB_FS_Name_Pattern()))::TEXT;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

-- Produce a valid name for a schema generated for the Federated Server 
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Schema_Name(server_name TEXT, schema_name TEXT)
RETURNS NAME
AS $$
DECLARE
    server_full_name text := @extschema@.__CDB_FS_Generate_Server_Name(server_name, check_existence := true);
    hash_value text := md5(server_full_name::text || '__' || schema_name::text);
    schema_name text := format('%s%s%s', @extschema@.__CDB_FS_Name_Pattern(), 'schema_', hash_value);
BEGIN
    RETURN schema_name::name;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Produce a valid name for a role generated for the Federated Server
-- This needs to include the current database in its hash to avoid collisions in clusters with more than one database
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Server_Role_Name(server_name TEXT)
RETURNS NAME
AS $$
DECLARE
    server_full_name text := @extschema@.__CDB_FS_Generate_Server_Name(server_name, check_existence := true);
    hash_value text := md5(current_database()::text || '__' || server_full_name::text);
    role_name text := format('%s%s%s', @extschema@.__CDB_FS_Name_Pattern(), 'role_', hash_value);
BEGIN
    RETURN role_name::name;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Creates (if not exist) a schema to place the objects for a remote schema
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Create_Schema(server_name TEXT, schema_name TEXT)
RETURNS NAME
AS $$
DECLARE
    schema_name text := @extschema@.__CDB_FS_Generate_Schema_Name(server_name, schema_name);
    role_name text := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_name);
BEGIN
    BEGIN
        EXECUTE 'CREATE SCHEMA IF NOT EXISTS ' || quote_ident(schema_name) || ' AUTHORIZATION ' || quote_ident(role_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'TODO: This needs a better error handling after reviewing permissions';
    END;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


-- List registered servers
-- TODO: Decide whether we want to show extra config (extensions, fetch_size, use_remote_estimate)
-- TODO: Handle multiple user mappings in the same server
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Servers(server TEXT DEFAULT '%')
RETURNS TABLE (
    name        text,
    driver      text,
    host        text,
    port        text,
    dbname      text,
    readmode    text,
    username    text
)
AS $$
DECLARE
    server_name text := concat(@extschema@.__CDB_FS_Name_Pattern(), server);
BEGIN
    RETURN QUERY SELECT 
        -- Name as shown to the user
        @extschema@.__CDB_FS_Extract_Server_Name(s.srvname) AS "Name",

        -- Which driver are we using (postgres_fdw, odbc_fdw...)
        f.fdwname::text AS "Driver",

        -- Read options from pg_foreign_server
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'host') AS "Host",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'port') AS "Port",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'dbname') AS "DBName",
        CASE WHEN (SELECT NOT option_value::boolean FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'updatable') THEN 'read-only' ELSE 'read-write' END AS "ReadMode",

        -- Read username from pg_user_mappings
        (SELECT option_value FROM pg_options_to_table(u.umoptions) WHERE option_name LIKE 'user') AS "Username"
    FROM pg_foreign_server s
    JOIN pg_foreign_data_wrapper f ON f.oid=s.srvfdw
    LEFT JOIN pg_user_mappings u
    ON u.srvid = s.oid
    WHERE s.srvname ILIKE server_name
    ORDER BY 1;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Take a config jsonb and transform it to an input suitable for
-- _CDB_SetUp_User_PG_FDW_Server
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_credentials_to_user_mapping(input_config JSONB)
RETURNS jsonb
AS $$
DECLARE
    user_mapping jsonb := json_build_object(
        'user_mapping',
        jsonb_build_object('user', input_config->'credentials'->'username',
                           'password', input_config->'credentials'->'password')
        );
BEGIN
    RETURN (input_config - 'credentials')::jsonb || user_mapping;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Take a config jsonb as input and return it augmented with default
-- options
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_add_default_options(input_config jsonb)
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


CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Register_PG(server TEXT, config JSONB)
RETURNS void
AS $$
DECLARE
    -- TODO: Check and handle existing servers (if needed)
    final_name text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := false);
    final_config jsonb := @extschema@.__CDB_FS_credentials_to_user_mapping(@extschema@.__CDB_FS_add_default_options(config));
BEGIN
    PERFORM @extschema@._CDB_SetUp_User_PG_FDW_Server(final_name, final_config::json);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Unregister(server TEXT)
RETURNS void
AS $$
DECLARE
    final_name text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
BEGIN
    EXECUTE @extschema@._CDB_Drop_User_PG_FDW_Server(fdw_input_name := final_name, force := true);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
