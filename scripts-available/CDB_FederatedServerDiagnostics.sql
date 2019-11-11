--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------

--
-- Import a foreign table if it does not exist
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Import_If_Not_Exists(server_internal name, remote_schema name, remote_table name)
RETURNS void
AS $$
DECLARE
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
BEGIN
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = remote_table
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I',
                    remote_schema, remote_table, server_internal, local_schema);
    END IF;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- Get the version of a remote PG server
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Foreign_Server_Version_PG(server_internal name)
RETURNS text
AS $$
DECLARE
    remote_schema name := 'pg_catalog';
    remote_table name := 'pg_settings';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
    remote_server_version text;
BEGIN
    PERFORM @extschema@.__CDB_FS_Import_If_Not_Exists(server_internal, remote_schema, remote_table);

    BEGIN
        EXECUTE format('
            SELECT setting FROM %I.%I WHERE name = ''server_version'';
        ', local_schema, remote_table) INTO remote_server_version;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Not enough permissions to access the server "%"',
                        @extschema@.__CDB_FS_Extract_Server_Name(server_internal);
    END;

    RETURN remote_server_version;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- Get the PostGIS extension version of a remote PG server
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Foreign_PostGIS_Version_PG(server_internal name)
RETURNS text
AS $$
DECLARE
    remote_schema name := 'pg_catalog';
    remote_table name := 'pg_extension';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
    remote_postgis_version text;
BEGIN
    PERFORM @extschema@.__CDB_FS_Import_If_Not_Exists(server_internal, remote_schema, remote_table);

    BEGIN
        EXECUTE format('
            SELECT extversion FROM %I.%I WHERE extname = ''postgis'';
        ', local_schema, remote_table) INTO remote_postgis_version;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Not enough permissions to access the server "%"',
                        @extschema@.__CDB_FS_Extract_Server_Name(server_internal);
    END;

    RETURN remote_postgis_version;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- Get the foreign server options of a remote PG server
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Foreign_Server_Options_PG(server_internal name)
RETURNS jsonb
AS $$
DECLARE
    res jsonb := '{}';
    opt record;
BEGIN
    -- See https://www.postgresql.org/docs/current/catalog-pg-foreign-server.html
    -- See https://www.postgresql.org/docs/current/functions-info.html
    FOR opt IN
        SELECT (pg_options_to_table(srvoptions)).* FROM pg_foreign_server WHERE srvname = server_internal
    LOOP
        res := res || jsonb_build_object(opt.option_name, opt.option_value);
    END LOOP;
    RETURN res;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- Collect and return diagnostics info from a remote PG into a jsonb
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Server_Diagnostics_PG(server_internal name)
RETURNS jsonb
AS $$
DECLARE
    remote_server_version  text := @extschema@.__CDB_FS_Foreign_Server_Version_PG(server_internal);
    remote_postgis_version text := @extschema@.__CDB_FS_Foreign_PostGIS_Version_PG(server_internal);
    remote_server_options jsonb := @extschema@.__CDB_FS_Foreign_Server_Options_PG(server_internal);
BEGIN
    RETURN jsonb_build_object(
        'server_version', remote_server_version,
        'postgis_version', remote_postgis_version,
        'server_options', remote_server_options
    );
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;



--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- Collect and return diagnostics info from a remote PG into a jsonb
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_Diagnostics(server TEXT)
RETURNS jsonb
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name => server, check_existence => true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN @extschema@.__CDB_FS_Server_Diagnostics_PG(server_internal);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
