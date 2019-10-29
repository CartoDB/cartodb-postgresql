
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


-- Registers a new server
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Register_PG(server TEXT, config JSONB)
RETURNS void
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := false);
    final_config json := @extschema@.__CDB_FS_credentials_to_user_mapping(@extschema@.__CDB_FS_add_default_options(config));
    role_name name;
    row record;
    option record;
BEGIN
    IF NOT EXISTS (SELECT * FROM pg_extension WHERE extname = 'postgres_fdw') THEN
        RAISE EXCEPTION 'postgres_fdw extension is not installed'
            USING HINT = 'Please install it with `CREATE EXTENSION postgres_fdw`';
    END IF;
    
    -- We only create server and roles if the server didn't exist before
    IF NOT EXISTS (SELECT * FROM pg_foreign_server WHERE srvname = server_internal) THEN
        BEGIN
            EXECUTE FORMAT('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw', server_internal);
            role_name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server);
            EXECUTE FORMAT('CREATE ROLE %I NOLOGIN', role_name);
            EXECUTE FORMAT('GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO %I', role_name);
            EXECUTE FORMAT('GRANT USAGE ON FOREIGN SERVER %I TO %I', server_internal, role_name);
            EXECUTE FORMAT('ALTER SERVER %I OWNER TO %I', server_internal, role_name);
            -- NOTE: we use a PUBLIC user mapping but control access to the SERVER
            -- so that we don't need to create a mapping for every user nor store credentials elsewhere
            EXECUTE FORMAT ('CREATE USER MAPPING FOR public SERVER %I', server_internal);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Could not create server %: %', server, SQLERRM
                USING HINT = 'Please clean the remaining objects"';
        END;
    END IF;

    -- Add new options
    FOR row IN SELECT p.key, p.value from lateral json_each_text(final_config->'server') p
    LOOP
        IF NOT EXISTS (
            WITH a AS (
                SELECT split_part(unnest(srvoptions), '=', 1) AS options FROM pg_foreign_server WHERE srvname=server_internal
            ) SELECT * from a where options = row.key)
        THEN
            EXECUTE FORMAT('ALTER SERVER %I OPTIONS (ADD %I %L)', server_internal, row.key, row.value);
        ELSE
            EXECUTE FORMAT('ALTER SERVER %I OPTIONS (SET %I %L)', server_internal, row.key, row.value);
        END IF;
    END LOOP;

    -- Update user mapping settings
    FOR option IN SELECT o.key, o.value from lateral json_each_text(final_config->'user_mapping') o
    LOOP
        IF NOT EXISTS (
            WITH a AS (
                SELECT split_part(unnest(umoptions), '=', 1) as options from pg_user_mappings WHERE srvname = server_internal AND usename = 'public'
            ) SELECT * from a where options = option.key)
        THEN
            EXECUTE FORMAT('ALTER USER MAPPING FOR PUBLIC SERVER %I OPTIONS (ADD %I %L)', server_internal, option.key, option.value);
        ELSE
            EXECUTE FORMAT('ALTER USER MAPPING FOR PUBLIC SERVER %I OPTIONS (SET %I %L)', server_internal, option.key, option.value);
        END IF;
    END LOOP;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Drops a registered server and all the objects associated with it
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Unregister(server TEXT)
RETURNS void
AS $$
DECLARE
    server_internal text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server);
BEGIN
    EXECUTE FORMAT ('DROP USER MAPPING FOR public SERVER %I', server_internal);
    EXECUTE FORMAT ('DROP OWNED BY %I CASCADE', role_name);
    EXECUTE FORMAT ('DROP ROLE %I', role_name);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
