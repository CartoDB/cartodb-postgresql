-- Auxiliary overviews FUNCTIONS

-- Maximum zoom level for which overviews may be created
CREATE OR REPLACE FUNCTION @extschema@._CDB_MaxOverviewLevel()
RETURNS INTEGER
AS $$
  BEGIN
    -- Zoom level will be limited so that both tile coordinates
    -- and gridding coordinates within a tile up to 1px
    -- (i.e. tile coordinates / 256)
    -- can be stored in a 32-bit signed integer.
    -- We have 31 bits por positive numbers
    -- For zoom level Z coordinates range from 0 to 2^Z-1, so they
    -- need Z bits, and need 8 bits more to address pixels within a tile
    -- (gridding), so we'll limit Z to a maximum of 31 - 8
    RETURN 23;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Maximum zoom level usable with integer coordinates
CREATE OR REPLACE FUNCTION @extschema@._CDB_MaxZoomLevel()
RETURNS INTEGER
AS $$
  BEGIN
    RETURN 31;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Information about tables in a schema.
-- If the schema name parameter is NULL, then tables from all schemas
-- that may contain user tables are returned.
-- For each table, the regclass, schema name and table name are returned.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_UserTablesInSchema(schema_name text DEFAULT NULL)
RETURNS TABLE(table_regclass REGCLASS, schema_name TEXT, table_name TEXT)
AS $$
  SELECT
    c.oid::regclass AS table_regclass,
    n.nspname::text AS schema_name,
    c.relname::text AS table_relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r'
  AND c.relname NOT IN ('cdb_tablemetadata', 'cdb_analysis_catalog', 'cdb_conf', 'spatial_ref_sys')
  AND CASE WHEN schema_name IS NULL
             THEN n.nspname NOT IN ('pg_catalog', 'information_schema', 'topology', '@extschema@')
           ELSE n.nspname = schema_name
           END;
$$ LANGUAGE 'sql' STABLE PARALLEL SAFE;

-- Pattern that can be used to detect overview tables and Extract
-- the intended zoom level from the table name.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewTableDiscriminator()
RETURNS TEXT
AS $$
  BEGIN
    RETURN '\A_vovw_(\d+)_';
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;
-- substring(tablename from _CDB_OverviewTableDiscriminator())


-- Pattern matched by the overview tables of a given base table name.
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewTablePattern(base_table TEXT)
RETURNS TEXT
AS $$
  BEGIN
    RETURN @extschema@._CDB_OverviewTableDiscriminator() || base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;
-- tablename SIMILAR TO _CDB_OverviewTablePattern(base_table)

-- Name of an overview table, given the base table name and the Z level
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewTableName(base_table TEXT, z INTEGER)
RETURNS TEXT
AS $$
  BEGIN
    RETURN '_vovw_' || z::text || '_' || base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Condition to check if a tabla is an overview table of some base table
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_IsOverviewTableOf(base_table TEXT, otable TEXT)
RETURNS BOOLEAN
AS $$
  BEGIN
    RETURN otable SIMILAR TO @extschema@._CDB_OverviewTablePattern(base_table);
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Extract the Z level from an overview table name
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewTableZ(otable TEXT)
RETURNS INTEGER
AS $$
  BEGIN
    RETURN substring(otable from @extschema@._CDB_OverviewTableDiscriminator())::integer;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Name of the base table corresponding to an overview table
-- Scope: private.
CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewBaseTableName(overview_table TEXT)
RETURNS TEXT
AS $$
  BEGIN
    IF @extschema@._CDB_OverviewTableZ(overview_table) IS NULL THEN
      RETURN overview_table;
    ELSE
      RETURN regexp_replace(overview_table, @extschema@._CDB_OverviewTableDiscriminator(), '');
    END IF;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@._CDB_OverviewBaseTable(overview_table REGCLASS)
RETURNS REGCLASS
AS $$
  DECLARE
    table_name TEXT;
    schema_name TEXT;
    base_name TEXT;
    base_table REGCLASS;
  BEGIN
    SELECT * FROM @extschema@._cdb_split_table_name(overview_table) INTO schema_name, table_name;
    base_name := @extschema@._CDB_OverviewBaseTableName(table_name);
    IF base_name != table_name THEN
      base_table := Format('%I.%I', schema_name, base_name)::regclass;
    ELSE
      base_table := overview_table;
    END IF;
    RETURN base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Schema and relation names of a table given its reloid
-- Scope: private.
-- Parameters
--   reloid: oid of the table.
-- Return (schema_name, table_name)
-- note that returned names will be quoted if necessary
CREATE OR REPLACE FUNCTION @extschema@._cdb_split_table_name(reloid REGCLASS, OUT schema_name TEXT, OUT table_name TEXT)
AS $$
  BEGIN
    SELECT n.nspname, c.relname
    INTO STRICT schema_name, table_name
    FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = reloid;
  END
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;

-- Schema and relation names of a table given its reloid
-- Scope: private.
-- Parameters
--   reloid: oid of the table.
-- Return (schema_name, table_name)
-- note that returned names will be quoted if necessary
CREATE OR REPLACE FUNCTION @extschema@._cdb_schema_name(reloid REGCLASS)
RETURNS TEXT
AS $$
  DECLARE
    schema_name TEXT;
  BEGIN
    SELECT n.nspname
    INTO STRICT schema_name
    FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = reloid;
    RETURN schema_name;
  END
$$ LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE;
