-- Return the estimated size of user data. Used for quota checking.
CREATE OR REPLACE FUNCTION CDB_UserDataSize(schema_name TEXT)
RETURNS bigint AS
$$
DECLARE
  quota_vector INT8;
  quota_raster INT8;
BEGIN
  -- TODO: double check queries. Maybe use CDB_TableMetadata for lookup?
  --  Also, "table_name" sounds sensible to search_path

  -- Division by 2 is for not counting the_geom_webmercator
  SELECT COALESCE(INT8(SUM(pg_total_relation_size(schema_name || '.' || table_name)) / 2), 0) INTO quota_vector
  FROM information_schema.tables
  WHERE table_catalog = current_database() AND table_schema = schema_name
    AND table_name != 'spatial_ref_sys'
    AND table_name != 'cdb_tablemetadata'
    AND table_type = 'BASE TABLE'
    -- exclude raster overview tables
    AND table_name NOT IN (
      SELECT o_table_name FROM raster_overviews
      WHERE o_table_schema = schema_name AND o_table_catalog = current_database()
    )
    -- exclude raster "main" tables
    AND table_name NOT IN (
      SELECT r_table_name FROM raster_overviews
      WHERE r_table_name = table_name
        AND o_table_schema = schema_name AND o_table_catalog = current_database()
    );

  SELECT COALESCE(INT8(SUM(pg_total_relation_size(schema_name || '.' || table_name))), 0) INTO quota_raster
  FROM information_schema.tables
  WHERE table_catalog = current_database() AND table_schema = schema_name
    AND table_name != 'spatial_ref_sys'
    AND table_name != 'cdb_tablemetadata'
    AND table_type = 'BASE TABLE'
    -- exclude raster overview tables
    AND table_name NOT IN (
      SELECT o_table_name FROM raster_overviews
      WHERE o_table_schema = schema_name AND o_table_catalog = current_database()
    )
    -- filter to raster "main" tables
    AND table_name IN (
      SELECT r_table_name FROM raster_overviews
      WHERE r_table_name = table_name
        AND o_table_schema = schema_name AND o_table_catalog = current_database()
    );

  RETURN quota_vector + quota_raster;
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
