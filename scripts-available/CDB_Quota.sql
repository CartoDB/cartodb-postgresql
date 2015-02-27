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
    SELECT table_name FROM information_schema.tables
      WHERE table_catalog = current_database() AND table_schema = schema_name
        AND table_name != 'spatial_ref_sys'
        AND table_name != 'cdb_tablemetadata'
        AND table_type = 'BASE TABLE'
  ),
  table_cat AS (
    SELECT
      table_name,
      EXISTS(select * from raster_tables where o_table_name = table_name) AS is_overview,
      EXISTS(SELECT * FROM raster_tables WHERE r_table_name = table_name) AS is_raster
    FROM user_tables
  ),
  sizes AS (
    SELECT COALESCE(INT8(SUM(pg_total_relation_size('"' || schema_name || '"."' || table_name || '"')))) table_size,
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
LANGUAGE 'plpgsql' VOLATILE;


-- Return the estimated size of user data. Used for quota checking.
-- Implicit schema version for backwards compatibility
CREATE OR REPLACE FUNCTION CDB_UserDataSize()
RETURNS bigint AS
$$
  SELECT public.CDB_UserDataSize('public');
$$
LANGUAGE 'sql' VOLATILE;

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
LANGUAGE 'plpgsql' VOLATILE;


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
LANGUAGE 'plpgsql' VOLATILE STRICT;


CREATE OR REPLACE FUNCTION CDB_SetUserQuotaInBytes(bytes int8)
RETURNS int8 AS
$$
BEGIN
  return public.CDB_SetUserQuotaInBytes('public', bytes);
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;
