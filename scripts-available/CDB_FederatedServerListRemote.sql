--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Schemas_PG(server_internal name)
RETURNS TABLE(remote_schema name)
AS $$
DECLARE
    -- Import schemata from the information schema
    --
    -- "The view schemata contains all schemas in the current database
    -- that the current user has access to (by way of being the owner
    -- or having some privilege)."
    -- See https://www.postgresql.org/docs/11/infoschema-schemata.html
    --
    -- "The information schema is defined in the SQL standard and can
    -- therefore be expected to be portable and remain stable"
    -- See https://www.postgresql.org/docs/11/information-schema.html
    inf_schema name := 'information_schema';
    remote_table name := 'schemata';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, inf_schema);
BEGIN
    -- Import the foreign schemata if not done
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = remote_table
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I', inf_schema, remote_table, server_internal, local_schema);
    END IF;

    -- Return the result we're interested in. Exclude toast and temp schemas
    RETURN QUERY EXECUTE format('
        SELECT schema_name::name AS remote_schema FROM %I.%I
        WHERE schema_name NOT LIKE %s
        ORDER BY remote_schema
    ', local_schema, remote_table, '''pg_%''');
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Tables_PG(server_internal name, remote_schema name)
RETURNS TABLE(remote_table name)
AS $func$
DECLARE
    -- Import `tables` from the information schema
    --
    -- "The view tables contains all tables and views defined in the
    -- current database. Only those tables and views are shown that
    -- the current user has access to (by way of being the owner or
    -- having some privilege)."
    -- https://www.postgresql.org/docs/11/infoschema-tables.html

    -- Create local target schema if it does not exists
    inf_schema name := 'information_schema';
    remote_table name := 'tables';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, inf_schema);
BEGIN
    -- Import the foreign `tables` if not done
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = 'tables'
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I', inf_schema, remote_table, server_internal, local_schema);
    END IF;

    -- Return the result we're interested in
    -- Note: in this context, schema names are not to be quoted
    RETURN QUERY EXECUTE format($q$
        SELECT table_name::name AS remote_table FROM %I.%I WHERE table_schema = '%s' ORDER BY table_name
        $q$, local_schema, remote_table, remote_schema);
END
$func$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- List remote schemas in a federated server that the current user has access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Schemas(remote_server name)
RETURNS TABLE(remote_schema name)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := remote_server, check_existence := true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY SELECT @extschema@.__CDB_FS_List_Foreign_Schemas_PG(server_internal);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, remote_server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List remote tables in a federated server that the current user has access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Tables(remote_server name, remote_schema name)
RETURNS TABLE(remote_table name)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := remote_server, check_existence := true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY SELECT @extschema@.__CDB_FS_List_Foreign_Tables_PG(server_internal, remote_schema);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, remote_server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
