CREATE OR REPLACE FUNCTION cartodb._CDB_total_relation_size(_schema_name TEXT, _table_name TEXT)
RETURNS bigint AS
$$
DECLARE relation_size bigint := 0;
BEGIN
  BEGIN
    SELECT pg_total_relation_size(format('"%s"."%s"', _schema_name, _table_name)) INTO relation_size;
  EXCEPTION
    WHEN undefined_table OR OTHERS THEN
      RAISE NOTICE 'cartodb._CDB_total_relation_size(''%'', ''%'') caught error: % (%)', _schema_name, _table_name, SQLERRM, SQLSTATE;
  END;
  RETURN relation_size;
END;
$$
LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;

-- Return the estimated size of user data. Used for quota checking.
CREATE OR REPLACE FUNCTION CDB_UserDataSize(schema_name TEXT)
RETURNS bigint AS
$$
DECLARE
  total_size INT8;
BEGIN
  WITH raster_tables AS (
    SELECT o_table_name, r_table_name FROM raster_overviews
      WHERE o_table_schema = schema_name AND o_table_catalog = current_database()
  ),
  user_tables AS (
    SELECT table_name FROM _CDB_NonAnalysisTablesInSchema(schema_name)
  ),
  table_cat AS (
    SELECT
      table_name,
      (
        EXISTS(select * from raster_tables where o_table_name = table_name)
        OR table_name SIMILAR TO _CDB_OverviewTableDiscriminator() || '[\w\d]*'
      ) AS is_overview,
      EXISTS(SELECT * FROM raster_tables WHERE r_table_name = table_name) AS is_raster
    FROM user_tables
  ),
  sizes AS (
    SELECT COALESCE(INT8(SUM(cartodb._CDB_total_relation_size(schema_name, table_name)))) table_size,
      CASE
        WHEN is_overview THEN 0
	WHEN is_raster THEN 1
	ELSE 0.5 -- Division by 2 is for not counting the_geom_webmercator
      END AS multiplier FROM table_cat GROUP BY is_overview, is_raster
  )
  SELECT sum(table_size*multiplier)::int8 INTO total_size FROM sizes;

  IF total_size IS NOT NULL THEN
    RETURN total_size;
  ELSE
    RETURN 0;
  END IF;
END;
$$
LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;

-- Return data (schema, table_name, size, row_count) from the user tables
CREATE OR REPLACE FUNCTION cartodb.CDB_UserTablesData(schema_name TEXT)
RETURNS TABLE(schema_name text, table_name text, size bigint, row_count bigint, table_type text) AS
$$
  SELECT    schema_name as schema_name,
            pc.relname::text as table_name,
            CASE
                WHEN table_type = 'regular' THEN pg_total_relation_size('"' || schema_name || '"."' || pc.relname::text || '"')/2
                WHEN table_type = 'raster'  THEN pg_total_relation_size('"' || schema_name || '"."' || pc.relname::text || '"')
            END as size,
            COALESCE(pc.reltuples::bigint, 0) as row_count,
            table_type
    FROM
    (
      SELECT table_name, 'regular' as table_type
        FROM _CDB_NonAnalysisTablesInSchema(schema_name)
        WHERE (table_name SIMILAR TO _CDB_OverviewTableDiscriminator() || '[\w\d]*') = FALSE
      UNION ALL
      SELECT o_table_name as table_name, 'raster' as table_type
        FROM raster_overviews
        WHERE o_table_schema = schema_name
        AND o_table_catalog = current_database()
    ) _tables
    INNER JOIN pg_class pc ON (pc.relname = _tables.table_name)
    INNER JOIN pg_namespace pn ON (pc.relnamespace = pn.oid AND pn.nspname = schema_name);

$$
LANGUAGE SQL STRICT STABLE PARALLEL SAFE;

-- Return the estimated size of user data. Used for quota checking.
-- Implicit schema version for backwards compatibility
CREATE OR REPLACE FUNCTION CDB_UserDataSize()
RETURNS bigint AS
$$
  SELECT CDB_UserDataSize('public');
$$
LANGUAGE 'sql' VOLATILE PARALLEL UNSAFE;

-- Triggers cannot have declared arguments: pbfact float8, qmax int8, schema_name text
CREATE OR REPLACE FUNCTION CDB_CheckQuota()
RETURNS trigger AS
$$
DECLARE
  pbfact float8;
  qmax int8;
  schema_name text;
  dice float8;
  quota float8;
BEGIN
  IF TG_NARGS = 3 THEN
    schema_name := TG_ARGV[2];
    IF cartodb.schema_exists(schema_name) = false THEN
      RAISE EXCEPTION 'Invalid schema name "%"', schema_name;
    END IF;
  ELSE
    schema_name := 'public';
  END IF;

  -- By default try to use quota function, and if not present then rely on the one specified by params
  BEGIN
    EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name) INTO qmax;
  EXCEPTION WHEN undefined_function THEN
    BEGIN
      IF TG_NARGS >= 2 AND TG_ARGV[1] <> '-1' THEN
        qmax := TG_ARGV[1];
      ELSE
        RAISE EXCEPTION 'Missing "%"._CDB_UserQuotaInBytes()', schema_name;
      END IF;
    END;
  END;

  pbfact := TG_ARGV[0];

  dice := random();

  IF dice < pbfact THEN
    RAISE DEBUG 'Checking quota on table % (dice:%, needed:<%)', TG_RELID::text, dice, pbfact;

    IF qmax = 0 THEN
      RETURN NEW;
    END IF;

    SELECT public.CDB_UserDataSize(schema_name) INTO quota;
    IF quota > qmax THEN
      RAISE EXCEPTION 'Quota exceeded by %KB', (quota-qmax)/1024;
    ELSE RAISE DEBUG 'User quota in bytes: % < % (max allowed)', quota, qmax;
    END IF;
  END IF;

  RETURN NEW;
END;
$$
LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION CDB_SetUserQuotaInBytes(schema_name text, bytes int8)
RETURNS int8 AS
$$
DECLARE
  sql text;
BEGIN
  IF cartodb.schema_exists(schema_name::text) = false THEN
    RAISE EXCEPTION 'Invalid schema name "%"', schema_name::text;
  END IF;

  sql := 'CREATE OR REPLACE FUNCTION "' || schema_name::text || '"._CDB_UserQuotaInBytes() '
    || 'RETURNS int8 AS $X$ SELECT ' || bytes
    || '::int8 $X$ LANGUAGE sql IMMUTABLE';
  EXECUTE sql;

  return bytes;
END
$$
LANGUAGE 'plpgsql' VOLATILE STRICT PARALLEL UNSAFE;


CREATE OR REPLACE FUNCTION CDB_SetUserQuotaInBytes(bytes int8)
RETURNS int8 AS
$$
BEGIN
  return public.CDB_SetUserQuotaInBytes('public', bytes);
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT PARALLEL UNSAFE;
