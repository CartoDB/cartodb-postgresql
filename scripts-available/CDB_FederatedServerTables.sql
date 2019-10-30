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
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.__CDB_FS_Column_Is_Geometry(input_table REGCLASS, colname NAME)
RETURNS boolean
AS $$
BEGIN
    PERFORM atttypid FROM pg_catalog.pg_attribute
        WHERE attrelid = input_table
           AND attname = colname
           AND atttypid = 'geometry'::regtype;
    RETURN FOUND;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


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
$$ LANGUAGE SQL;



--
-- Set up a Federated Table
--
-- Precondition: the federated server has to be set up via
-- CDB_SetUp_PG_Federated_Server
--
-- Postcondition: it generates a view in the schema of the user that
-- can be used through SQL and Maps API's.
--
-- E.g:
-- SELECT cartodb.CDB_SetUp_PG_Federated_Table(
--   'amazon',                  -- mandatory, name of the federated server
--   'my_remote_schema',        -- mandatory, schema name
--   'my_remote_table',         -- mandatory, table name
--   'id',                      -- mandatory, name of the id column
--   'geom',                    -- optional, name of the geom column, preferably in 4326
--   'webmercator'              -- optional, should be in 3857 if present
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
    -- Use geom_column as default for webmercator_column
    IF webmercator_column IS NULL THEN
        webmercator_column := geom_column;
    END IF;
    
    IF local_name IS NULL THEN
        local_name := remote_table;
    END IF;

    -- Import the foreign table
    EXECUTE FORMAT ('IMPORT FOREIGN SCHEMA %I LIMIT TO (%I) FROM SERVER %I INTO %I;', remote_schema, remote_table, server_internal, local_schema);
    src_table := format('%I.%I', local_schema, remote_table);
    
    --- Grant SELECT to fdw role (TODO: Re-enable if needed)
    --- EXECUTE FORMAT ('GRANT SELECT ON %I.%I TO %I;', fdw_objects_name, table_name, fdw_objects_name);
    
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
        geom_expression := format('@postgisschema@.ST_Transform(t.%I, 4326) AS the_geom', geom_column);
    END IF;

    IF webmercator_column IS NULL
    THEN
        webmercator_expression := 'NULL AS the_geom_webmercator';
    ELSIF @postgisschema@.Find_SRID(local_schema::varchar, remote_table::varchar, webmercator_column::varchar) = 3857
    THEN
        webmercator_expression := format('t.%I AS the_geom_webmercator', webmercator_column);
    ELSE
        -- It needs an ST_Transform to 3857
        webmercator_expression := format('@postgisschema@.ST_Transform(t.%I, 3857) AS the_geom_webmercator', webmercator_column);
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
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Could not import table "%" as "%": %', remote_table, local_name, SQLERRM;
    END;

    -- TODO: Handle this Grant perms to the view
    -- EXECUTE format('GRANT SELECT ON %I TO %s', table_name, fdw_objects_name);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
