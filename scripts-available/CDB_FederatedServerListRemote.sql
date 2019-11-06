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
    role_name name := @extschema@.__CDB_FS_Generate_Server_Role_Name(server_internal);
BEGIN
    -- Import the foreign schemata table
    IF NOT EXISTS (
        SELECT * FROM pg_class
        WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = local_schema)
        AND relname = remote_table
    ) THEN
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I',
                    inf_schema, remote_table, server_internal, local_schema);
    END IF;

    -- Return the result we're interested in. Exclude toast and temp schemas
    BEGIN
        RETURN QUERY EXECUTE format('
            SELECT schema_name::name AS remote_schema FROM %I.%I
            WHERE schema_name NOT LIKE %s
            ORDER BY remote_schema
        ', local_schema, remote_table, '''pg_%''');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Not enough permissions to access the server "%"',
                        @extschema@.__CDB_FS_Extract_Server_Name(server_internal);
    END;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List the names of the tables in a remote PG schema
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
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I',
                    inf_schema, remote_table, server_internal, local_schema);
    END IF;

    -- Note: in this context, schema names are not to be quoted
    RETURN QUERY EXECUTE format($q$
        SELECT table_name::name AS remote_table FROM %I.%I WHERE table_schema = '%s' ORDER BY table_name
        $q$, local_schema, remote_table, remote_schema);
END
$func$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--
-- List the columns in a remote PG schema
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Columns_PG(server_internal name, remote_schema name)
RETURNS TABLE(table_name name, column_name name, column_type text)
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
        EXECUTE format('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I',
                    inf_schema, remote_col_table, server_internal, local_schema);
    END IF;

    -- Note: in this context, schema names are not to be quoted
    -- We join with the geometry columns to change the type `USER-DEFINED` 
    -- by its appropiate geometry and srid
    RETURN QUERY EXECUTE format($q$
        SELECT 
            a.table_name::name,
            a.column_name::name,
            COALESCE(b.column_type, a.data_type)::TEXT as column_type
        FROM
            %I.%I a
        LEFT JOIN
            @extschema@.__CDB_FS_List_Foreign_Geometry_Columns_PG('%s', '%s') b
        ON a.table_name = b.table_name AND a.column_name = b.column_name
        WHERE table_schema = '%s'
        ORDER BY a.table_name, a.column_name $q$,
        local_schema, remote_col_table,
        server_internal, remote_schema,
        remote_schema);
END
$func$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- List the geometry columns in a remote PG schema
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Foreign_Geometry_Columns_PG(server_internal name, remote_schema name, postgis_schema name DEFAULT 'public')
RETURNS TABLE(table_name name, column_name name, column_type text)
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
            SELECT 
                f_table_name::NAME as table_name,
                f_geometry_column::NAME as column_name,
                type::TEXT || ',' || srid::TEXT as column_type
            FROM
            (
                SELECT * FROM %I.%I UNION ALL SELECT * FROM %I.%I
            ) _geo_views
            WHERE f_table_schema = '%s'
        $q$,
            local_schema, remote_geometry_view,
            local_schema, remote_geography_view,
            remote_schema);
    EXCEPTION WHEN OTHERS THEN
        RAISE INFO 'Could not find Postgis installation in the remote "%" schema in server "%"',
                    postgis_schema, @extschema@.__CDB_FS_Extract_Server_Name(server_internal);
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
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name => server, check_existence => true);
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
-- For registered tables it returns also the associated configuration
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Server_List_Remote_Tables(server TEXT, remote_schema TEXT)
RETURNS TABLE(
    registered boolean,
    remote_table TEXT,
    local_qualified_name TEXT,
    id_column_name TEXT,
    geom_column_name TEXT,
    webmercator_column_name TEXT,
    columns JSON
    )
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name => server, check_existence => true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY
            SELECT
                coalesce(registered_tables.registered, false)::boolean as registered,
                foreign_tables.remote_table::text as remote_table,
                registered_tables.local_qualified_name as local_qualified_name,
                registered_tables.id_column_name as id_column_name,
                registered_tables.geom_column_name as geom_column_name,
                registered_tables.webmercator_column_name as webmercator_column_name,
                remote_columns.columns as columns
            FROM
                @extschema@.__CDB_FS_List_Foreign_Tables_PG(server_internal, remote_schema) foreign_tables
            LEFT JOIN
                @extschema@.__CDB_FS_List_Registered_Tables(server_internal, remote_schema) registered_tables
            ON foreign_tables.remote_table = registered_tables.remote_table
            LEFT JOIN
                (   -- Extract and group columns with their remote table
                    SELECT  table_name,
                            json_agg(json_build_object('Name', column_name, 'Type', column_type)) as columns
                    FROM @extschema@.__CDB_FS_List_Foreign_Columns_PG(server_internal, remote_schema)
                    GROUP BY table_name
                ) remote_columns
            ON foreign_tables.remote_table = remote_columns.table_name
            ORDER BY foreign_tables.remote_table;
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
RETURNS TABLE(column_n name, column_t text)
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name => server, check_existence => true);
    server_type name := @extschema@.__CDB_FS_server_type(server_internal);
BEGIN
    IF remote_table IS NULL THEN
        RAISE EXCEPTION 'Remote table name cannot be NULL';
    END IF;

    CASE server_type
    WHEN 'postgres_fdw' THEN
        RETURN QUERY
        SELECT 
            column_name,
            column_type
        FROM @extschema@.__CDB_FS_List_Foreign_Columns_PG(server_internal, remote_schema)
        WHERE table_name = remote_table
        ORDER BY column_name;
    ELSE
        RAISE EXCEPTION 'Not implemented server type % for remote server %', server_type, remote_server;
    END CASE;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
