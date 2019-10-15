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
CREATE OR REPLACE FUNCTION @extschema@.__ft_add_default_readonly_options(input_config jsonb)
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


CREATE OR REPLACE FUNCTION @extschema@.__ft_is_numeric(input_table regclass, colname name)
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


CREATE OR REPLACE FUNCTION @extschema@.__ft_is_geometry(input_table regclass, colname name)
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


CREATE OR REPLACE FUNCTION @extschema@.__ft_getcolumns(input_table REGCLASS)
RETURNS SETOF NAME
AS $$
  SELECT
    a.attname as "colname"
  FROM
    pg_catalog.pg_attribute a
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



--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------

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
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Server(server_alias name, server_config jsonb)
RETURNS void
AS $$
DECLARE
    final_config jsonb;
BEGIN
    final_config := @extschema@.__ft_credentials_to_user_mapping(
        @extschema@.__ft_add_default_readonly_options(server_config)
    );
    PERFORM @extschema@._CDB_SetUp_User_PG_FDW_Server(server_alias, final_config::json);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


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
CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Table(
    server_alias name,
    schema_name name,
    table_name name,
    id_column name,
    geom_column name,
    webmercator_column name
)
RETURNS void
AS $$
DECLARE
    fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(server_alias);
    src_table REGCLASS;
    rest_of_cols TEXT[];
    geom_expression TEXT;
    webmercator_expression TEXT;
BEGIN
    -- Import the foreign table
    PERFORM @extschema@.CDB_SetUp_User_PG_FDW_Table(server_alias, schema_name, table_name);
    src_table := format('%s.%s', fdw_objects_name, table_name);

    -- Check id_column is numeric
    IF NOT @extschema@.__ft_is_numeric(src_table, id_column) THEN
        RAISE EXCEPTION 'non integer id_column "%"', id_colun;
    END IF;

    -- Check if the geom and mercator columns have a geometry type
    IF NOT @extschema@.__ft_is_geometry(src_table, geom_column) THEN
        RAISE EXCEPTION 'non geometry column "%"', geom_column;
    END IF;
    IF NOT @extschema@.__ft_is_geometry(src_table, webmercator_column) THEN
        RAISE EXCEPTION 'non geometry column "%"', webmercator_column;
    END IF;

    -- Get a list of columns excluding the id, geom and the_geom_webmercator
    SELECT ARRAY(
        SELECT quote_ident(c) FROM @extschema@.__ft_getcolumns(src_table) AS c
        WHERE c NOT IN (id_column, geom_column, webmercator_column)
    ) INTO rest_of_cols;

    -- Figure out whether a ST_Transform to 4326 is needed or not
    IF @postgisschema@.Find_SRID(fdw_objects_name::varchar, table_name::varchar, geom_column::varchar) = 4326
    THEN
        geom_expression := format('t.%I AS the_geom', geom_column);
    ELSE
        geom_expression := format('@postgisschema@.ST_Transform(t.%I, 4326) AS the_geom', geom_column);
    END IF;

    -- Figure out whether a ST_Transform to 3857 is needed or not
    IF Find_SRID(fdw_objects_name::varchar, table_name::varchar, webmercator_column::varchar) = 3857
    THEN
        webmercator_expression := format('t.%I AS the_geom_webmercator', webmercator_column);
    ELSE
        webmercator_expression := format('@postgisschema@.ST_Transform(t.%I, 3857) AS the_geom_webmercator', webmercator_column);
    END IF;

    -- Create a view with homogeneous CDB fields
    EXECUTE format(
        'CREATE OR REPLACE VIEW %1$I AS
            SELECT
                t.%2$I AS cartodb_id,
                %3$s,
                %4$s,
                %5$s
            FROM %6$s t',
        table_name,
        id_column,
        geom_expression,
        webmercator_expression,
        array_to_string(rest_of_cols, ','),
        src_table
    );

    -- Grant perms to the view
    EXECUTE format('GRANT SELECT ON %I TO %s', table_name, fdw_objects_name);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Table(
    server_alias name,
    schema_name name,
    table_name name,
    id_column name,
    geom_column name
)
RETURNS void
AS $$
    SELECT @extschema@.CDB_SetUp_PG_Federated_Table(
        server_alias,
        schema_name,
        table_name,
        id_column,
        geom_column,
        geom_column
    );
$$
LANGUAGE SQL VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION @extschema@.CDB_SetUp_PG_Federated_Table(
    server_alias name,
    schema_name name,
    table_name name,
    id_column name
)
RETURNS void
AS $$
DECLARE
    fdw_objects_name NAME := @extschema@.__CDB_User_FDW_Object_Names(server_alias);
    src_table REGCLASS;
    rest_of_cols TEXT[];
BEGIN
    -- Import the foreign table
    PERFORM @extschema@.CDB_SetUp_User_PG_FDW_Table(server_alias, schema_name, table_name);
    src_table := format('%s.%s', fdw_objects_name, table_name);

    -- Check id_column is numeric
    IF NOT @extschema@.__ft_is_numeric(src_table, id_column) THEN
        RAISE EXCEPTION 'non integer id_column "%"', id_colun;
    END IF;

    -- Get a list of columns excluding the id
    SELECT ARRAY(
        SELECT quote_ident(c) FROM @extschema@.__ft_getcolumns(src_table) AS c
        WHERE c NOT IN (id_column, 'the_geom', 'the_geom_webmercator')
    ) INTO rest_of_cols;

    -- Create a view with homogeneous CDB fields
    EXECUTE format(
        'CREATE OR REPLACE VIEW %1$I AS
            SELECT
                t.%2$I AS cartodb_id,
                NULL AS the_geom,
                NULL AS the_geom_webmercator,
                %3$s
            FROM %4$s t',
        table_name,
        id_column,
        array_to_string(rest_of_cols, ','),
        src_table
    );

    -- Grant perms to the view
    EXECUTE format('GRANT SELECT ON %I TO %s', table_name, fdw_objects_name);
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
