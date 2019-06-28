-- Read configuration parameter analysis_quota_factor, making it
-- accessible to regular users (which don't have access to cdb_conf)
CREATE OR REPLACE FUNCTION @extschema@._CDB_GetConfAnalysisQuotaFactor()
RETURNS float8 AS
$$
BEGIN
  RETURN @extschema@.CDB_Conf_GetConf('analysis_quota_factor')::text::float8;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE SECURITY DEFINER;


-- Get the factor (fraction of the quota) for Camshaft cached analysis tables
CREATE OR REPLACE FUNCTION @extschema@._CDB_AnalysisQuotaFactor()
RETURNS float8 AS
$$
DECLARE
  factor float8;
BEGIN
  -- We use a floating point cdb_conf parameter
  factor := @extschema@._CDB_GetConfAnalysisQuotaFactor();
  -- With a default value
  IF factor IS NULL THEN
    factor := 2;
  END IF;
  RETURN factor;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

-- This checks the space used up by Camshaft cached analysis tables.
-- An exception will be raised if the limits are exceeded.
-- The name of an analysis table is passed; this, in addition to the
-- db role that executes this function is used to determined which
-- analysis tables will be considered.
CREATE OR REPLACE FUNCTION @extschema@.CDB_CheckAnalysisQuota(table_name TEXT)
RETURNS void AS
$$
DECLARE
  schema_name TEXT;
  user_name TEXT;
  nominal_quota int8;
  cache_size float8;
BEGIN
  -- We rely on the search_path to determine the user's schema and
  -- check for all analysis tables in that schema.
  -- An alternative would be to use cdb_analysis_catalog to
  -- select analysis tables (cache_tables) from the same user, analysis or node.
  -- For example:
  --   SELECT unnest(cache_tables) FROM cdb_analysis_catalog
  --     WHERE username IN (SELECT username FROM cdb_analysis_catalog
  --       WHERE table_name::regclass = ANY (cache_tables));
  -- At the moment we're not using the provided table_name.

  SELECT current_schema() INTO schema_name;
  EXECUTE FORMAT('SELECT %I._CDB_UserQuotaInBytes();', schema_name) INTO nominal_quota;
  IF nominal_quota * @extschema@._CDB_AnalysisQuotaFactor() < @extschema@._CDB_AnalysisDataSize(schema_name) THEN
    -- The limit is defined by a factor applied to the total space quota for the user
    RAISE EXCEPTION 'Analysis cache space limits exceeded';
  END IF;
END;
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
