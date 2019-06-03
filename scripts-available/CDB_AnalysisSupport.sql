-- Internal auxiliar functions to deal with [Camshaft](https://github.com/cartodb/camshaft) cached analysis tables.

-- This function returns TRUE if a given table name corresponds to a Camshaft cached analysis table
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_IsAnalysisTableName(table_name TEXT)
RETURNS BOOLEAN
AS $$
  BEGIN
    RETURN table_name SIMILAR TO '\Aanalysis_[0-9a-f]{10}_[0-9a-f]{40}\Z';
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- This function returns a relation of Camshaft cached analysis tables in the given schema.
-- If the schema name parameter is NULL, then tables from all schemas
-- that may contain user tables are returned.
-- For each table, the regclass, schema name and table name are returned.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_AnalysisTablesInSchema(schema_name text DEFAULT NULL)
RETURNS TABLE(table_regclass REGCLASS, schema_name TEXT, table_name TEXT)
AS $$
  SELECT * FROM @extschema@._CDB_UserTablesInSchema(schema_name) WHERE @extschema@._CDB_IsAnalysisTableName(table_name);
$$ LANGUAGE 'sql' STABLE PARALLEL SAFE;

-- This function returns a relation user tables excluding analysis tables
-- If the schema name parameter is NULL, then tables from all schemas
-- that may contain user tables are returned.
-- For each table, the regclass, schema name and table name are returned.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_NonAnalysisTablesInSchema(schema_name text DEFAULT NULL)
RETURNS TABLE(table_regclass REGCLASS, schema_name TEXT, table_name TEXT)
AS $$
  SELECT * FROM @extschema@._CDB_UserTablesInSchema(schema_name) WHERE Not @extschema@._CDB_IsAnalysisTableName(table_name);
$$ LANGUAGE 'sql' STABLE PARALLEL SAFE;

-- Total spaced used up by Camshaft cached analysis tables in the given schema.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_AnalysisDataSize(schema_name TEXT DEFAULT NULL)
RETURNS bigint AS
$$
DECLARE
  total_size bigint;
BEGIN
  WITH analysis_tables AS (
    SELECT t.schema_name, t.table_name FROM @extschema@._CDB_AnalysisTablesInSchema(schema_name) t
  )
  SELECT COALESCE(INT8(SUM(@extschema@._CDB_total_relation_size(analysis_tables.schema_name, analysis_tables.table_name))))::int8
    INTO total_size FROM analysis_tables;
  IF total_size IS NOT NULL THEN
    RETURN total_size;
  ELSE
    RETURN 0;
  END IF;
END;
$$
LANGUAGE 'plpgsql' VOLATILE PARALLEL UNSAFE;
