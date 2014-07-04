-- Return the estimated size of user data. Used for quota checking.
CREATE OR REPLACE FUNCTION CDB_UserDataSize(schema_name TEXT)
RETURNS bigint AS
$$
  -- TODO: double check this query. Maybe use CDB_TableMetadata for lookup ?
  --       also, it's "table_name" sounds sensible to search_path
  --
  -- NOTE: division by 2 is an hack for the_geom_webmercator
  --
  SELECT coalesce(int8(sum(pg_total_relation_size(quote_ident(table_name))) / 2), 0)
    AS quota
  FROM information_schema.tables
  WHERE table_catalog = current_database() AND table_schema = schema_name
        AND table_name != 'spatial_ref_sys'
        AND table_name != 'cdb_tablemetadata'
        AND table_type = 'BASE TABLE';
$$
LANGUAGE 'sql' VOLATILE;


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
  -- Hack to support old versions of CDB_CheckQuota with 2 params but without schema_name
  IF TG_NARGS >= 2 AND TG_ARGV[1] <> '-1' THEN
    qmax := TG_ARGV[1];
  ELSE
    BEGIN
      EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name) INTO qmax;
      EXCEPTION WHEN undefined_function THEN
      RAISE EXCEPTION 'Missing "%"._CDB_UserQuotaInBytes()', schema_name;
    END;
  END IF;
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
  current_quota int8;
  schema_ok boolean;
  sql text;
BEGIN
  IF cartodb.schema_exists(schema_name::text) = false THEN
    RAISE EXCEPTION 'Invalid schema name "%"', schema_name::text;
  END IF;

  BEGIN
    EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name::text) INTO current_quota;
  EXCEPTION WHEN undefined_function THEN
    current_quota := 0;
  END;

  sql := 'CREATE OR REPLACE FUNCTION "' || schema_name::text || '"._CDB_UserQuotaInBytes() '
    || 'RETURNS int8 AS $X$ SELECT ' || bytes
    || '::int8 $X$ LANGUAGE sql IMMUTABLE';
  EXECUTE sql;

  return current_quota;
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
