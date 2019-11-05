--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------

--
-- This function is just a placement to store and use the pattern for
-- foreign object names
-- Servers:     cdb_fs_$(server_name)
-- Schemas:     cdb_fs_schema_$(md5sum(server_name || remote_schema_name))
-- Owner role:  cdb_fs_$(md5sum(current_database() || server_name)
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Name_Pattern()
RETURNS TEXT
AS $$
    SELECT 'cdb_fs_'::text;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

--
-- Produce a valid DB name for servers generated for the Federated Server
-- If check_existence is true, it'll throw if the server doesn't exists
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Server_Name(input_name TEXT, check_existence BOOL)
RETURNS NAME
AS $$
DECLARE
    internal_server_name text := format('%s%s', @extschema@.__CDB_FS_Name_Pattern(), input_name);
BEGIN
    IF input_name IS NULL THEN
        RAISE EXCEPTION 'Server name cannot be NULL';
    END IF;

    -- We discard anything that would be truncated
    IF (char_length(internal_server_name) >= 64) THEN
        RAISE EXCEPTION 'Server name (%) is too long to be used as identifier', input_name;
    END IF;

    IF (check_existence AND (NOT EXISTS (SELECT * FROM pg_foreign_server WHERE srvname = internal_server_name))) THEN
        RAISE EXCEPTION 'Server "%" does not exist', input_name;
    END IF;

    RETURN internal_server_name::name;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

--
-- Given the internal name for a remote server, it returns the name used by the user
-- Reverses __CDB_FS_Generate_Server_Name
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Extract_Server_Name(internal_server_name NAME)
RETURNS TEXT
AS $$
    SELECT right(internal_server_name,
            char_length(internal_server_name::TEXT) - char_length(@extschema@.__CDB_FS_Name_Pattern()))::TEXT;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

--
-- Produce a valid name for a schema generated for the Federated Server 
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Schema_Name(internal_server_name TEXT, schema_name TEXT)
RETURNS NAME
AS $$
DECLARE
    hash_value text := md5(internal_server_name::text || '__' || schema_name::text);
    schema_name text := format('%s%s%s', @extschema@.__CDB_FS_Name_Pattern(), 'schema_', hash_value);
BEGIN
    RETURN schema_name::name;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

--
-- Produce a valid name for a role generated for the Federated Server
-- This needs to include the current database in its hash to avoid collisions in clusters with more than one database
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Generate_Server_Role_Name(internal_server_name TEXT)
RETURNS NAME
AS $$
DECLARE
    hash_value text := md5(current_database()::text || '__' || internal_server_name::text);
    role_name text := format('%s%s%s', @extschema@.__CDB_FS_Name_Pattern(), 'role_', hash_value);
BEGIN
    RETURN role_name::name;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

--
-- Creates (if not exist) a schema to place the objects for a remote schema
-- The schema is with the same AUTHORIZATION as the server
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Create_Schema(internal_server_name TEXT, schema_name TEXT)
RETURNS NAME
AS $$
DECLARE
    schema_name text := @extschema@.__CDB_FS_Generate_Schema_Name(internal_server_name, schema_name);
    role_name text := @extschema@.__CDB_FS_Generate_Server_Role_Name(internal_server_name);
BEGIN
    -- By changing the local role to the owner of the server we have an
    -- easy way to check for permissions and keep all objects under the same owner
    BEGIN
        EXECUTE 'SET LOCAL ROLE ' || quote_ident(role_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Not enough permissions to access the server "%"',
                        @extschema@.__CDB_FS_Extract_Server_Name(internal_server_name);
    END;

    IF NOT EXISTS (SELECT oid FROM pg_namespace WHERE nspname = schema_name) THEN
        EXECUTE 'CREATE SCHEMA ' || quote_ident(schema_name) || ' AUTHORIZATION ' || quote_ident(role_name);
    END IF;
    RETURN schema_name;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- Returns the type of a server by internal name
-- Currently all of them should be postgres_fdw
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_server_type(remote_server name)
RETURNS name
AS $$
    SELECT f.fdwname
        FROM pg_foreign_server s
        JOIN pg_foreign_data_wrapper f ON s.srvfdw = f.oid
        WHERE s.srvname = remote_server;
$$
LANGUAGE SQL VOLATILE PARALLEL UNSAFE;

--
-- Take a config jsonb and transform it to an input suitable for _CDB_SetUp_User_PG_FDW_Server
-- 
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_credentials_to_user_mapping(input_config JSONB)
RETURNS jsonb
AS $$
DECLARE
    mapping jsonb := '{}'::jsonb;
BEGIN
    IF NOT (input_config ? 'credentials') THEN
        RAISE EXCEPTION 'Credentials are mandatory';
    END IF;
    
    -- For now, allow not passing username or password
    IF input_config->'credentials'->'username' IS NOT NULL THEN
        mapping := jsonb_build_object('user', input_config->'credentials'->'username');
    END IF;
    IF input_config->'credentials'->'password' IS NOT NULL THEN
        mapping := mapping || jsonb_build_object('password', input_config->'credentials'->'password');
    END IF;
    
    RETURN (input_config - 'credentials')::jsonb || jsonb_build_object('user_mapping', mapping);
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
    IF NOT (input_config ? 'server') THEN
        RAISE EXCEPTION 'Server information is mandatory';
    END IF;
    server_config := default_options || to_jsonb(input_config->'server');
    RETURN jsonb_set(input_config, '{server}'::text[], server_config);
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;


--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------


--
-- Registers a new PG server
--
-- Example config: '{
--     "server": {
--         "dbname": "fdw_target",
--         "host": "localhost",
--         "port": 5432,
--         "extensions": "postgis",
--         "updatable": "false",
--         "use_remote_estimate": "true",
--         "fetch_size": "1000"
--     },
--     "credentials": {
--         "username": "fdw_user",
--         "password": "foobarino"
--     }
-- }'
--
-- The configuration from __CDB_FS_add_default_options will be appended
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Register_PG(server TEXT, config JSONB)
RETURNS void
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := false);
    final_config json := @extschema@.__CDB_FS_credentials_to_user_mapping(@extschema@.__CDB_FS_add_default_options(config));
    role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
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
            -- TODO: Delete this IF before merging to make sure nobody creates a role
            -- that is later used automatically by us granting them all permissions in the foreign server
            -- TODO: This is here to help debugging during development (so failures to destroy objects are allowed)
            -- TODO
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
                EXECUTE FORMAT('CREATE ROLE %I NOLOGIN', role_name);
            END IF;
            EXECUTE FORMAT('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', current_database(), role_name);
            EXECUTE FORMAT('GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO %I', role_name);
            EXECUTE FORMAT('GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO %I', role_name);
            EXECUTE FORMAT('GRANT USAGE ON FOREIGN SERVER %I TO %I', server_internal, role_name);
            EXECUTE FORMAT('ALTER SERVER %I OWNER TO %I', server_internal, role_name);
            EXECUTE FORMAT ('CREATE USER MAPPING FOR %I SERVER %I', role_name, server_internal);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Could not create server %: %', server, SQLERRM
                USING HINT = 'Please clean the left over objects';
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
                SELECT split_part(unnest(umoptions), '=', 1) as options from pg_user_mappings WHERE srvname = server_internal AND usename = role_name
            ) SELECT * from a where options = option.key)
        THEN
            EXECUTE FORMAT('ALTER USER MAPPING FOR %I SERVER %I OPTIONS (ADD %I %L)', role_name, server_internal, option.key, option.value);
        ELSE
            EXECUTE FORMAT('ALTER USER MAPPING FOR %I SERVER %I OPTIONS (SET %I %L)', role_name, server_internal, option.key, option.value);
        END IF;
    END LOOP;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- Drops a registered server and all the objects associated with it
-- 
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Unregister(server TEXT)
RETURNS void
AS $$
DECLARE
    server_internal text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
BEGIN
    SET client_min_messages = ERROR;
    BEGIN
        EXECUTE FORMAT ('DROP USER MAPPING FOR %I SERVER %I', role_name, server_internal);
        EXECUTE FORMAT ('DROP OWNED BY %I CASCADE', role_name);
        EXECUTE FORMAT ('DROP ROLE %I', role_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Not enough permissions to drop the server "%"', server;
    END;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List registered servers
-- 
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
        @extschema@.__CDB_FS_server_type(s.srvname)::text AS "Driver",

        -- Read options from pg_foreign_server
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'host') AS "Host",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'port') AS "Port",
        (SELECT option_value FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'dbname') AS "DBName",
        CASE WHEN (SELECT NOT option_value::boolean FROM pg_options_to_table(s.srvoptions) WHERE option_name LIKE 'updatable') THEN 'read-only' ELSE 'read-write' END AS "ReadMode",

        -- Read username from pg_user_mappings
        (SELECT option_value FROM pg_options_to_table(u.umoptions) WHERE option_name LIKE 'user') AS "Username"
    FROM pg_foreign_server s
    LEFT JOIN pg_user_mappings u
    ON u.srvid = s.oid
    WHERE s.srvname ILIKE server_name
    ORDER BY 1;
END
$$
LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;


--
-- Grant access to a server
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Grant_Access(server TEXT, usernames text[])
RETURNS void
AS $$
DECLARE
    server_internal text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    server_role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
    user_role TEXT;
    username TEXT;
BEGIN
    FOREACH username IN ARRAY usernames
    LOOP
        user_role := @extschema@._CDB_User_RoleFromUsername(username);
        IF (user_role IS NULL) THEN
            RAISE EXCEPTION 'User role "%" does not exists', username;
        END IF;
        EXECUTE format('GRANT %I TO %I', server_role_name, user_role);
    END loop;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- Revoke access to a server
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Revoke_Access(server TEXT, usernames text[])
RETURNS void
AS $$
DECLARE
    server_internal text := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    server_role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
    user_role TEXT;
    username TEXT;
BEGIN
    FOREACH username IN ARRAY usernames
    LOOP
        user_role := @extschema@._CDB_User_RoleFromUsername(username);
        IF (user_role IS NULL) THEN
            RAISE EXCEPTION 'User role "%" does not exists', username;
        END IF;
        EXECUTE format('REVOKE %I FROM %I', server_role_name, user_role);
    END loop;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
