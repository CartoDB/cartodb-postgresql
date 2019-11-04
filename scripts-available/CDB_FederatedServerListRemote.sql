--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------

--
-- List the schemas of a remote PG server
-- 
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
    role_name text := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
BEGIN
    -- Import the foreign schemata table
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

--
-- List the tables from a remote PG schema
-- 
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
        AND relname = remote_table
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


--
-- List the columns from a remote PG table
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Columns_PG(server_internal name, remote_schema name, remote_table name)
RETURNS TABLE(column_name name, column_type text)
AS $func$
DECLARE
    -- Import `columns` from the information schema
    --
    -- "The view columns contains information about all table columns (or view columns)
    -- in the database. System columns (oid, etc.) are not included. Only those columns 
    -- are shown that the current user has access to (by way of being the owner or having some privilege)."
    -- https://www.postgresql.org/docs/11/infoschema-columns.html

    -- Create local target schema if it does not exists
    inf_schema name := 'information_schema';
    remote_col_table name := 'columns';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, inf_schema);
BEGIN
    -- Import the foreign `columns` if not done
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = remote_col_table
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I', inf_schema, remote_col_table, server_internal, local_schema);
    END IF;

    -- Return the result we're interested in
    -- Note: in this context, remote schema and remote table names are not to be quoted
    RETURN QUERY EXECUTE format($q$
        SELECT 
            a.column_name::name, COALESCE(b.column_type, a.data_type)::TEXT as column_type
        FROM %I.%I a
        LEFT JOIN @extschema@.__CDB_FS_List_Foreign_Geometry_Columns_PG('%s', '%s', '%s') b ON a.column_name = b.column_name
        WHERE table_schema = '%s' AND table_name = '%s'
        ORDER BY column_name$q$,
        local_schema, remote_col_table,
        server_internal, remote_schema, remote_table,
        remote_schema, remote_table);
END
$func$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List the columns from a remote PG table
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Geometry_Columns_PG(server_internal name, remote_schema name, remote_table name, postgis_schema name DEFAULT 'public')
RETURNS TABLE(column_name name, column_type text)
AS $func$
DECLARE
    -- Import `geometry_columns` and `geography_columns` from the postgis schema
    -- We assume that postgis is installed in the public schema

    -- Create local target schema if it does not exists
    remote_geometry_view name := 'geometry_columns';
    remote_geography_view name := 'geography_columns';
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, postgis_schema);
BEGIN
    -- Import the foreign `geometry_columns` and `geography_columns` if not done
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = remote_geometry_view
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I, %I) FROM SERVER %I INTO %I',
                    postgis_schema, remote_geometry_view, remote_geography_view, server_internal, local_schema);
    END IF;

    BEGIN
    -- Note: We return both the type and srid as the type
        RETURN QUERY EXECUTE format($q$
            SELECT  f_geometry_column::NAME as column_name,
                    type::TEXT || ',' || srid::TEXT as column_type
                FROM
                (
                    SELECT * FROM %I.%I UNION ALL SELECT * FROM %I.%I
                ) _geo_views
                WHERE
                    f_table_schema = '%s' AND
                    f_table_name = '%s'
        $q$,
            local_schema, remote_geometry_view,
            local_schema, remote_geography_view,
            remote_schema, remote_table);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not find Postgis installation in the remote "%" schema', postgis_schema;
        RETURN;
    END;
END
$func$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- List remote schemas in a federated server that the current user has access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Schemas(server TEXT)
RETURNS TABLE(remote_schema name)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY SELECT @extschema@.__CDB_FS_List_Foreign_Schemas_PG(server_internal);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List remote tables in a federated server that the current user has access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Tables(server TEXT, remote_schema TEXT)
RETURNS TABLE(remote_table name)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
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

--
-- List the columns of a remote table in a federated server that the current user has access to.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Columns(
    server TEXT,
    remote_schema TEXT,
    remote_table TEXT)
RETURNS TABLE(column_name name, column_type text)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY SELECT * FROM @extschema@.__CDB_FS_List_Foreign_Columns_PG(server_internal, remote_schema, remote_table);
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, remote_server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
