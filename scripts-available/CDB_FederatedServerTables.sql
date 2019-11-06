--------------------------------------------------------------------------------
-- Private functions
--------------------------------------------------------------------------------

--
-- Checks if a column is of integer type
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Column_Is_Integer(input_table REGCLASS, colname NAME)
RETURNS boolean
AS $$
BEGIN
    PERFORM atttypid FROM pg_catalog.pg_attribute
       WHERE attrelid = input_table
         AND attname = colname
         AND atttypid IN (SELECT oid FROM pg_type
           WHERE typname IN
             ('smallint', 'integer', 'bigint', 'int2', 'int4', 'int8'));
    RETURN FOUND;
END
$$
LANGUAGE PLPGSQL STABLE PARALLEL UNSAFE;

--
-- Checks if a column is of geometry type
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Column_Is_Geometry(input_table REGCLASS, colname NAME)
RETURNS boolean
AS $$
BEGIN
    PERFORM atttypid FROM pg_catalog.pg_attribute
        WHERE attrelid = input_table
           AND attname = colname
           AND atttypid = '@postgisschema@.geometry'::regtype;
    RETURN FOUND;
END
$$
LANGUAGE PLPGSQL STABLE PARALLEL UNSAFE;

--
-- Returns the name of all the columns from a table
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_GetColumns(input_table REGCLASS)
RETURNS SETOF NAME
AS $$
    SELECT
        a.attname as "colname"
    FROM pg_catalog.pg_attribute a
    WHERE
        a.attnum > 0
            AND NOT a.attisdropped
            AND a.attrelid = (
                SELECT c.oid
                FROM pg_catalog.pg_class c
                LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE c.oid = input_table::oid
            )
    ORDER BY a.attnum;
$$ LANGUAGE SQL STABLE PARALLEL UNSAFE;

--
-- Returns the id column from a view definition
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Get_View_id_column(view_def TEXT)
RETURNS TEXT
AS $$
    WITH column_definitions AS
    (
        SELECT regexp_split_to_array(regexp_split_to_table(view_def, '\n'), ' ') AS col_def
    )
    SELECT split_part(col_def[array_length(col_def, 1) - 2], '.', 2)
    FROM column_definitions where col_def[array_length(col_def, 1)] = 'cartodb_id,'
    LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

--
-- Returns the geom column from a view definition
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Get_View_geom_column(view_def TEXT)
RETURNS TEXT
AS $$
    WITH column_definitions AS
    (
        SELECT regexp_split_to_array(regexp_split_to_table(view_def, '\n'), ' ') AS col_def
    )
    SELECT trim(trailing ',' FROM split_part(
            CASE WHEN col_def[array_length(col_def, 1) - 2] = '4326)' THEN col_def[array_length(col_def, 1) - 3]
            ELSE col_def[array_length(col_def, 1) - 2]
            END, '.', 2))
    FROM column_definitions
    WHERE col_def[array_length(col_def, 1)] = 'the_geom,'
    LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

--
-- Returns the webmercatorcolumn from a view definition
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Get_View_webmercator_column(view_def TEXT)
RETURNS TEXT
AS $$
    WITH column_definitions AS
    (
        SELECT regexp_split_to_array(regexp_split_to_table(view_def, '\n'), ' ') AS col_def
    )
    SELECT trim(trailing ',' FROM split_part(
            CASE WHEN col_def[array_length(col_def, 1) - 2] = '3857)' THEN col_def[array_length(col_def, 1) - 3]
            ELSE col_def[array_length(col_def, 1) - 2]
            END, '.', 2))
    FROM column_definitions
    WHERE col_def[array_length(col_def, 1)] = 'the_geom_webmercator,'
    LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;


--
-- List all registered tables in a server + schema
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_List_Registered_Tables(
    server_internal NAME,
    remote_schema TEXT
    )
RETURNS TABLE(
    registered boolean,
    remote_table TEXT,
    local_qualified_name TEXT,
    id_column_name TEXT,
    geom_column_name TEXT,
    webmercator_column_name TEXT
    )
AS $$
DECLARE
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
BEGIN
    RETURN QUERY SELECT
        true as registered,
        source_table::text as remote_table,
        format('%I.%I', dependent_schema, dependent_view)::text as local_qualified_name,
        @extschema@.__CDB_FS_Get_View_id_column(view_definition) as id_column_name,
        @extschema@.__CDB_FS_Get_View_geom_column(view_definition) as geom_column_name,
        @extschema@.__CDB_FS_Get_View_webmercator_column(view_definition) as webmercator_column_name
    FROM
    (
        SELECT DISTINCT
            dependent_ns.nspname as dependent_schema,
            dependent_view.relname as dependent_view,
            source_table.relname as source_table,
            pg_get_viewdef(dependent_view.oid) as view_definition
        FROM pg_depend
        JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
        JOIN pg_class as dependent_view ON pg_rewrite.ev_class = dependent_view.oid
        JOIN pg_class as source_table ON pg_depend.refobjid = source_table.oid
        JOIN pg_namespace dependent_ns ON dependent_ns.oid = dependent_view.relnamespace
        JOIN pg_namespace source_ns ON source_ns.oid = source_table.relnamespace
        WHERE
        source_ns.nspname = local_schema
        ORDER BY 1,2
    ) _aux;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

--
-- Sets up a Federated Table
--
-- Precondition: the federated server has to be set up via
-- CDB_Federated_Server_Register_PG
--
-- Postcondition: it generates a view in the schema of the user that
-- can be used through SQL and Maps API's.
-- If the table was already exported, it will be dropped and re-imported
--
-- E.g:
-- SELECT cartodb.CDB_SetUp_PG_Federated_Table(
--   'amazon',                  -- mandatory, name of the federated server
--   'my_remote_schema',        -- mandatory, schema name
--   'my_remote_table',         -- mandatory, table name
--   'id',                      -- mandatory, name of the id column
--   'geom',                    -- optional, name of the geom column, preferably in 4326
--   'webmercator'              -- optional, should be in 3857 if present
--   'local_name'               -- optional, name of the local view (uses the remote_name if not declared)
-- );
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Table_Register(
    server TEXT,
    remote_schema TEXT,
    remote_table TEXT,
    id_column TEXT,
    geom_column TEXT DEFAULT NULL,
    webmercator_column TEXT DEFAULT NULL,
    local_name NAME DEFAULT NULL
)
RETURNS void
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := false);
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
    src_table REGCLASS;

    rest_of_cols TEXT[];
    geom_expression TEXT;
    webmercator_expression TEXT;
    carto_columns_expression TEXT[];
BEGIN
    IF remote_table IS NULL THEN
        RAISE EXCEPTION 'Remote table name cannot be NULL';
    END IF;

    -- Use geom_column as default for webmercator_column
    IF webmercator_column IS NULL THEN
        webmercator_column := geom_column;
    END IF;
    
    IF local_name IS NULL THEN
        local_name := remote_table;
    END IF;

    -- Import the foreign table
    -- Drop the old view / table if there was one
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = local_schema AND table_name = remote_table) THEN
        EXECUTE @extschema@.CDB_Federated_Table_Unregister(server, remote_schema, remote_table);
    END IF;
    BEGIN
        EXECUTE FORMAT('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I;',
                        remote_schema, remote_table, server_internal, local_schema);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Could not import schema "%" of server "%"', remote_schema, server;
    END;
    
    BEGIN
        src_table := format('%I.%I', local_schema, remote_table);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Could not import table "%.%" of server "%"', remote_schema, remote_table, server;
    END;

    -- Check id_column is numeric
    IF NOT @extschema@.__CDB_FS_Column_Is_Integer(src_table, id_column) THEN
        RAISE EXCEPTION 'non integer id_column "%"', id_column;
    END IF;

    -- Check if the geom and mercator columns have a geometry type (if provided)
    IF geom_column IS NOT NULL AND NOT @extschema@.__CDB_FS_Column_Is_Geometry(src_table, geom_column) THEN
        RAISE EXCEPTION 'non geometry column "%"', geom_column;
    END IF;
    IF webmercator_column IS NOT NULL AND NOT @extschema@.__CDB_FS_Column_Is_Geometry(src_table, webmercator_column) THEN
        RAISE EXCEPTION 'non geometry column "%"', webmercator_column;
    END IF;

    -- Get a list of columns excluding the id, geom and the_geom_webmercator
    SELECT ARRAY(
        SELECT quote_ident(c) FROM @extschema@.__CDB_FS_GetColumns(src_table) AS c
        WHERE c NOT IN (SELECT * FROM (SELECT unnest(ARRAY[id_column, geom_column, webmercator_column, 'cartodb_id', 'the_geom', 'the_geom_webmercator']) col) carto WHERE carto.col IS NOT NULL)
    ) INTO rest_of_cols;

    IF geom_column IS NULL
    THEN
        geom_expression := 'NULL AS the_geom';
    ELSIF @postgisschema@.Find_SRID(local_schema::varchar, remote_table::varchar, geom_column::varchar) = 4326
    THEN
        geom_expression := format('t.%I AS the_geom', geom_column);
    ELSE
        -- It needs an ST_Transform to 4326
        geom_expression := format('@postgisschema@.ST_Transform(t.%I,4326) AS the_geom', geom_column);
    END IF;

    IF webmercator_column IS NULL
    THEN
        webmercator_expression := 'NULL AS the_geom_webmercator';
    ELSIF @postgisschema@.Find_SRID(local_schema::varchar, remote_table::varchar, webmercator_column::varchar) = 3857
    THEN
        webmercator_expression := format('t.%I AS the_geom_webmercator', webmercator_column);
    ELSE
        -- It needs an ST_Transform to 3857
        webmercator_expression := format('@postgisschema@.ST_Transform(t.%I,3857) AS the_geom_webmercator', webmercator_column);
    END IF;

    -- CARTO columns expressions
    carto_columns_expression := ARRAY[
        format('t.%1$I AS cartodb_id', id_column),
        geom_expression,
        webmercator_expression
    ];

    -- Create a view with homogeneous CDB fields
    BEGIN
        EXECUTE format(
            'CREATE OR REPLACE VIEW %1$I AS
                SELECT %2s
                FROM %3$s t',
            local_name,
            array_to_string(carto_columns_expression || rest_of_cols, ','),
            src_table
        );
    EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE EXCEPTION 'Could not import table "%" as "%": "%" already exists', remote_table, local_name, local_name;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Could not import table "%" as "%": %', remote_table, local_name, SQLERRM;
    END;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

--
-- Unregisters a remote table. Any dependent object will be dropped
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_Federated_Table_Unregister(
    server TEXT,
    remote_schema TEXT,
    remote_table TEXT
)
RETURNS void
AS $$
DECLARE
    server_internal name := @extschema@.__CDB_FS_Generate_Server_Name(input_name := server, check_existence := false);
    local_schema name := @extschema@.__CDB_FS_Create_Schema(server_internal, remote_schema);
BEGIN
    EXECUTE FORMAT ('DROP FOREIGN TABLE %I.%I CASCADE;', local_schema, remote_table);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
