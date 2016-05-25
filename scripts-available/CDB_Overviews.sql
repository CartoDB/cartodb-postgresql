-- Maximum zoom level for which overviews may be created
CREATE OR REPLACE FUNCTION _CDB_MaxOverviewLevel()
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
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Maximum zoom level usable with integer coordinates
CREATE OR REPLACE FUNCTION _CDB_MaxZoomLevel()
RETURNS INTEGER
AS $$
  BEGIN
    RETURN 31;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Information about tables in a schema.
-- If the schema name parameter is NULL, then tables from all schemas
-- that may contain user tables are returned.
-- For each table, the regclass, schema name and table name are returned.
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_UserTablesInSchema(schema_name text DEFAULT NULL)
RETURNS TABLE(table_regclass REGCLASS, schema_name TEXT, table_name TEXT)
AS $$
  SELECT
    c.oid::regclass AS table_regclass,
    n.nspname::text AS schema_name,
    c.relname::text AS table_relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r'
  AND c.relname NOT IN ('cdb_tablemetadata', 'spatial_ref_sys')
  AND CASE WHEN schema_name IS NULL
             THEN n.nspname NOT IN ('pg_catalog', 'information_schema', 'topology', 'cartodb')
           ELSE n.nspname = schema_name
           END;
$$ LANGUAGE 'sql';

-- Pattern that can be used to detect overview tables and Extract
-- the intended zoom level from the table name.
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_OverviewTableDiscriminator()
RETURNS TEXT
AS $$
  BEGIN
    RETURN '\A_vovw_(\d+)_';
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;
-- substring(tablename from _CDB_OverviewTableDiscriminator())


-- Pattern matched by the overview tables of a given base table name.
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_OverviewTablePattern(base_table TEXT)
RETURNS TEXT
AS $$
  BEGIN
    RETURN _CDB_OverviewTableDiscriminator() || base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;
-- tablename SIMILAR TO _CDB_OverviewTablePattern(base_table)

-- Name of an overview table, given the base table name and the Z level
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_OverviewTableName(base_table TEXT, z INTEGER)
RETURNS TEXT
AS $$
  BEGIN
    RETURN '_vovw_' || z::text || '_' || base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Condition to check if a tabla is an overview table of some base table
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_IsOverviewTableOf(base_table TEXT, otable TEXT)
RETURNS BOOLEAN
AS $$
  BEGIN
    RETURN otable SIMILAR TO _CDB_OverviewTablePattern(base_table);
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Extract the Z level from an overview table name
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_OverviewTableZ(otable TEXT)
RETURNS INTEGER
AS $$
  BEGIN
    RETURN substring(otable from _CDB_OverviewTableDiscriminator())::integer;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Name of the base table corresponding to an overview table
-- Scope: private.
CREATE OR REPLACE FUNCTION _CDB_OverviewBaseTableName(overview_table TEXT)
RETURNS TEXT
AS $$
  BEGIN
    IF _CDB_OverviewTableZ(overview_table) IS NULL THEN
      RETURN overview_table;
    ELSE
      RETURN regexp_replace(overview_table, _CDB_OverviewTableDiscriminator(), '');
    END IF;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION _CDB_OverviewBaseTable(overview_table REGCLASS)
RETURNS REGCLASS
AS $$
  DECLARE
    table_name TEXT;
    schema_name TEXT;
    base_name TEXT;
    base_table REGCLASS;
  BEGIN
    SELECT * FROM _cdb_split_table_name(overview_table) INTO schema_name, table_name;
    base_name := _CDB_OverviewBaseTableName(table_name);
    IF base_name != table_name THEN
      base_table := Format('%I.%I', schema_name, base_name)::regclass;
    ELSE
      base_table := overview_table;
    END IF;
    RETURN base_table;
  END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Schema and relation names of a table given its reloid
-- Scope: private.
-- Parameters
--   reloid: oid of the table.
-- Return (schema_name, table_name)
-- note that returned names will be quoted if necessary
CREATE OR REPLACE FUNCTION _cdb_split_table_name(reloid REGCLASS, OUT schema_name TEXT, OUT table_name TEXT)
AS $$
  BEGIN
    SELECT n.nspname, c.relname
    INTO STRICT schema_name, table_name
    FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid = reloid;
  END
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Schema and relation names of a table given its reloid
-- Scope: private.
-- Parameters
--   reloid: oid of the table.
-- Return (schema_name, table_name)
-- note that returned names will be quoted if necessary
CREATE OR REPLACE FUNCTION _cdb_schema_name(reloid REGCLASS)
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
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Remove a dataset's existing  overview tables.
-- Scope: public
-- Parameters:
--   reloid: oid of the table.
CREATE OR REPLACE FUNCTION CDB_DropOverviews(reloid REGCLASS)
RETURNS void
AS $$
DECLARE
    row record;
    schema_name TEXT;
    table_name TEXT;
BEGIN
    SELECT * FROM _cdb_split_table_name(reloid) INTO schema_name, table_name;
    FOR row IN
        SELECT * FROM CDB_Overviews(reloid)
    LOOP
        EXECUTE Format('DROP TABLE %s;', row.overview_table);
        RAISE NOTICE 'Dropped overview for level %: %', row.z, row.overview_table;
    END LOOP;
END;
$$ LANGUAGE PLPGSQL VOLATILE;



-- Return existing overviews (if any) for a given dataset table
-- Scope: public
-- Parameters
--   reloid: oid of the input table.
-- Return relation of overviews for the table with
-- the base table oid,
-- z level of the overview and overview table oid, ordered by z.
CREATE OR REPLACE FUNCTION CDB_Overviews(reloid REGCLASS)
RETURNS TABLE(base_table REGCLASS, z integer, overview_table REGCLASS)
AS $$
  DECLARE
    schema_name TEXT;
    base_table_name TEXT;
  BEGIN
    SELECT * FROM _cdb_split_table_name(reloid) INTO schema_name, base_table_name;
    RETURN QUERY SELECT
      reloid AS base_table,
      _CDB_OverviewTableZ(table_name) AS z,
      table_regclass AS overview_table
      FROM _CDB_UserTablesInSchema(schema_name)
      WHERE _CDB_IsOverviewTableOf((SELECT relname FROM pg_class WHERE oid=reloid), table_name)
      ORDER BY z;
  END
$$ LANGUAGE PLPGSQL;

-- Return existing overviews (if any) for multiple dataset tables.
-- Scope: public
-- Parameters
--   tables: Array of input tables oids
-- Return relation of overviews for the table with
-- the base table oid,
-- z level of the overview and overview table oid, ordered by z.
-- Note: CDB_Overviews can be applied to the result of CDB_QueryTablesText
-- to obtain the overviews applicable to a query.
CREATE OR REPLACE FUNCTION CDB_Overviews(tables regclass[])
RETURNS TABLE(base_table REGCLASS, z integer, overview_table REGCLASS)
AS $$
  SELECT
    base_table::regclass AS base_table,
    _CDB_OverviewTableZ(table_name) AS z,
    table_regclass AS overview_table
    FROM
      _CDB_UserTablesInSchema(), unnest(tables) base_table
    WHERE
      schema_name = _cdb_schema_name(base_table)
      AND _CDB_IsOverviewTableOf((SELECT relname FROM pg_class WHERE oid=base_table), table_name)
    ORDER BY base_table, z;
$$ LANGUAGE SQL;

-- Calculate the estimated extent of a cartodbfy'ed table.
-- Scope: private.
-- Parameters
--   reloid: oid of the input table.
-- Return value A box2d extent in 3857.
CREATE OR REPLACE FUNCTION _cdb_estimated_extent(reloid REGCLASS)
RETURNS box2d
AS $$
  DECLARE
    ext box2d;
    ext_query text;
    table_id record;
  BEGIN

    SELECT n.nspname AS schema_name, c.relname table_name INTO STRICT table_id
      FROM pg_class c JOIN pg_namespace n on n.oid = c.relnamespace WHERE c.oid = reloid::oid;

    ext_query = format(
      'SELECT ST_EstimatedExtent(''%1$s'', ''%2$s'', ''%3$s'');',
      table_id.schema_name, table_id.table_name, 'the_geom_webmercator'
    );

    BEGIN
      EXECUTE ext_query INTO ext;
    EXCEPTION
        -- This is the typical ERROR: stats for "mytable" do not exist
        WHEN internal_error THEN
          -- Get stats and execute again
          EXECUTE format('ANALYZE %1$s', reloid);

          -- We check the geometry type in case the error is due to empty geometries
          IF _CDB_GeometryTypes(reloid) IS NULL THEN
            RETURN NULL;
          END IF;

          EXECUTE ext_query INTO ext;
    END;

    RETURN ext;
  END;
$$ LANGUAGE PLPGSQL VOLATILE;

-- Determine the max feature density of a given dataset.
-- Scope: private.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
--   nz: number of zoom levels to consider from z0 upward.
-- Return value: feature density (num_features / webmercator_squared_meters).
CREATE OR REPLACE FUNCTION _CDB_Feature_Density(reloid REGCLASS, nz integer)
RETURNS FLOAT8
AS $$
  DECLARE
    fd FLOAT8;
    min_features TEXT;
    n integer = 4;
    c FLOAT8;
  BEGIN
  -- TODO: for small total count or extents we could just:
  -- EXECUTE 'SELECT Count(*)/ST_Area(ST_Extent(the_geom_webmercator)) FROM ' || reloid::text || ';' INTO fd;

  -- min_features is a SQL subexpression which can depend on z and represents
  -- the minimum number of features to recursively consider a tile.
  -- We can either use a fixed minimum number of features per tile
  -- or a minimum feature density by dividing the number of features by
  -- the area of tiles at level Z: c*c*power(2, -2*z)
  -- with c = CDB_XYZ_Resolution(-8) (earth circumference)
  min_features = '500';
  SELECT CDB_XYZ_Resolution(-8) INTO c;

  -- We first compute a set of *seed* tiles, of the minimum Z level, z0, such that
  -- they cover the extent of the table and we have at least n of them in each
  -- linear dimension (i.e. at least n*n tiles cover the extent).
  -- We compute the number of features in these tiles, and recursively in
  -- subtiles up to level z0 + nz. Then we compute the maximum of the feature
  -- density (per tile area in webmercator squared meters) for all the
  -- considered tiles.
  EXECUTE Format('
    WITH RECURSIVE t(x, y, z, e) AS (
      WITH ext AS (SELECT _cdb_estimated_extent(%6$s) as g),
      base AS (
        SELECT
          least(
           -floor(log(2, (greatest(ST_XMax(ext.g)-ST_XMin(ext.g), ST_YMax(ext.g)-ST_YMin(ext.g))/(%4$s*%5$s))::numeric)),
           _CDB_MaxOverviewLevel()+1
          )::integer z
        FROM ext
      ),
      lim AS (
        SELECT
          FLOOR((ST_XMin(ext.g)+CDB_XYZ_Resolution(0)*128)/(CDB_XYZ_Resolution(base.z)*256))::integer x0,
          FLOOR((ST_XMax(ext.g)+CDB_XYZ_Resolution(0)*128)/(CDB_XYZ_Resolution(base.z)*256))::integer x1,
          FLOOR((CDB_XYZ_Resolution(0)*128-ST_YMin(ext.g))/(CDB_XYZ_Resolution(base.z)*256))::integer y1,
          FLOOR((CDB_XYZ_Resolution(0)*128-ST_YMax(ext.g))/(CDB_XYZ_Resolution(base.z)*256))::integer y0
        FROM ext, base
      ),
      seed AS (
        SELECT xt, yt, base.z, (
          SELECT count(*) FROM %1$s
            WHERE the_geom_webmercator && CDB_XYZ_Extent(xt, yt, base.z)
        ) e
        FROM base, lim, generate_series(lim.x0, lim.x1) xt, generate_series(lim.y0, lim.y1) yt
      )
      SELECT * from seed
      UNION ALL
      SELECT x*2 + xx, y*2 + yy, t.z+1, (
        SELECT count(*) FROM %1$s
          WHERE the_geom_webmercator && CDB_XYZ_Extent(x*2 + xx, y*2 + yy, t.z+1)
      )
      FROM t, base, (VALUES (0, 0), (0, 1), (1, 1), (1, 0)) AS c(xx, yy)
      WHERE t.e > %2$s AND t.z < least(base.z + %3$s, _CDB_MaxZoomLevel())
    )
    SELECT MAX(e/ST_Area(CDB_XYZ_Extent(x,y,z))) FROM t where e > 0;
  ', reloid::text, min_features, nz, n, c, reloid::oid)
  INTO fd;
  RETURN fd;
  END
$$ LANGUAGE PLPGSQL STABLE;

-- Experimental default strategy to assign a reference base Z level
-- to a cartodbfied table. The resulting Z level represents the
-- minimum scale level at which the table data can be rendered
-- without overcrowded results or loss of detail.
-- Parameters:
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
-- Return value: Z level as an integer
CREATE OR REPLACE FUNCTION _CDB_Feature_Density_Ref_Z_Strategy(reloid REGCLASS, tolerance_px FLOAT8 DEFAULT NULL)
RETURNS INTEGER
AS $$
  DECLARE
    lim FLOAT8;
    nz integer := 4;
    fd FLOAT8;
    c FLOAT8;
  BEGIN
    IF (tolerance_px IS NULL) OR tolerance_px = 0 THEN
      lim := 500;
    ELSE
      lim := floor(power(256/tolerance_px, 2))/2;
    END IF;

    -- Compute fd as an estimation of the (maximum) number
    -- of features per unit of tile area (in webmercator squared meters)
    SELECT _CDB_Feature_Density(reloid, nz) INTO fd;
    -- lim maximum number of (desiderable) features per tile
    -- we have c = 2*Pi*R = CDB_XYZ_Resolution(-8) (earth circumference)
    -- ta(z): tile area = power(c*power(2,-z), 2) = c*c*power(2,-2*z)
    -- => fd*ta(z) is the average number of features per tile at level z
    -- find minimum z so that fd*ta(z) <= lim
    -- compute a rough 'feature density' value
    SELECT CDB_XYZ_Resolution(-8) INTO c;
    RETURN least(_CDB_MaxOverviewLevel()+1, ceil(log(2.0, (c*c*fd/lim)::numeric)/2));
  END;
$$ LANGUAGE PLPGSQL STABLE;

-- Overview table name for a given Z level and base dataset or overview table
-- Scope: private.
-- Parameters:
--   ref reference table (can be the base table of the dataset or an existing
--   overview) from which the overview is being generated.
--   ref_z Z level of the reference table
--   overview_z Z level of the overview to be named, must be smaller than ref_z
-- Return value: the name to be used for the overview. The name is always
-- unqualified (does not include a schema name).
CREATE OR REPLACE FUNCTION _CDB_Overview_Name(ref REGCLASS, ref_z INTEGER, overview_z INTEGER)
RETURNS TEXT
AS $$
  DECLARE
    schema_name TEXT;
    base TEXT;
    suffix TEXT;
    is_overview BOOLEAN;
  BEGIN
    SELECT * FROM _cdb_split_table_name(ref) INTO schema_name, base;
    SELECT _CDB_OverviewBaseTableName(base) INTO base;
    RETURN _CDB_OverviewTableName(base, overview_z);
  END
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Sampling reduction method.
-- Valid for any kind of geometry.
-- Scope: private.
--   reloid original table (can be the base table of the dataset or an existing
--   overview) from which the overview is being generated.
--   ref_z Z level assigned to the original table
--   overview_z Z level of the overview to be generated, must be smaller than ref_z
-- Return value: Name of the generated overview table
CREATE OR REPLACE FUNCTION _CDB_Sampling_Reduce_Strategy(reloid REGCLASS, ref_z INTEGER, overview_z INTEGER, tolerance_px FLOAT8 DEFAULT NULL)
RETURNS REGCLASS
AS $$
  DECLARE
    overview_rel TEXT;
    fraction FLOAT8;
    base_name TEXT;
    class_info RECORD;
    num_samples INTEGER;
    schema_name TEXT;
    table_name TEXT;
  BEGIN
    overview_rel := _CDB_Overview_Name(reloid, ref_z, overview_z);
    -- TODO: compute fraction from tolerance_px if not NULL
    fraction := power(2, 2*(overview_z - ref_z));

    SELECT * FROM _cdb_split_table_name(reloid) INTO schema_name, table_name;

    EXECUTE Format('DROP TABLE IF EXISTS %I.%I CASCADE;', schema_name, overview_rel);

    -- Estimate number of rows
    SELECT reltuples, relpages FROM pg_class INTO STRICT class_info
      WHERE oid = reloid::oid;

    IF class_info.relpages < 2 OR fraction > 0.5 THEN
      -- We'll avoid possible CDB_RandomTids problems
      EXECUTE Format('
        CREATE TABLE %I AS SELECT * FROM %s WHERE random() < %s;
      ', overview_rel, reloid, fraction);
    ELSE
      num_samples := ceil(class_info.reltuples*fraction);
      EXECUTE Format('
        CREATE TABLE %4$I.%1$I AS SELECT * FROM %2$s
          WHERE ctid = ANY (
            ARRAY[
              (SELECT CDB_RandomTids(''%2$s'', %3$s))
            ]
          );
      ', overview_rel, reloid, num_samples, schema_name);
    END IF;

    RETURN Format('%I.%I', schema_name, overview_rel)::regclass;
  END;
$$ LANGUAGE PLPGSQL;

-- Register new overview table (post-creation chores)
-- Scope: private
-- Parameters:
--   dataset: oid of the input dataset table,  It must be a cartodbfy'ed table.
--   overview_table: oid of the overview table to be registered.
--   overview_z: intended Z level for the overview table
-- This function is declared SECURITY DEFINER so it executes with the privileges
-- of the function creator to have a chance to alter the privileges of the
-- overview table to match those of the dataset. It will only perform any change
-- if the overview table belgons to the same scheme as the dataset and it
-- matches the scheme naming for overview tables.
CREATE OR REPLACE FUNCTION _CDB_Register_Overview(dataset REGCLASS, overview_table REGCLASS, overview_z INTEGER)
RETURNS VOID
AS $$
  DECLARE
    sql TEXT;
    table_owner TEXT;
    dataset_scheme TEXT;
    dataset_name TEXT;
    overview_scheme TEXT;
    overview_name TEXT;
  BEGIN
    -- This function will only register a table as an overview table if it matches
    -- the overviews naming scheme for the dataset and z level and the table belongs
    -- to the same scheme as the the dataset
    SELECT * FROM _cdb_split_table_name(dataset) INTO dataset_scheme, dataset_name;
    SELECT * FROM _cdb_split_table_name(overview_table) INTO overview_scheme, overview_name;
    IF dataset_scheme = overview_scheme AND
       overview_name = _CDB_OverviewTableName(dataset_name, overview_z) THEN

      -- preserve the owner of the base table
      SELECT u.usename
        FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_user u ON (c.relowner=u.usesysid)
          JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = dataset_name::text AND n.nspname = dataset_scheme
        INTO table_owner;

      EXECUTE Format('ALTER TABLE IF EXISTS %s OWNER TO %I;', overview_table::text, table_owner);

      -- preserve the table privileges
      UPDATE pg_class c_to
        SET  relacl = c_from.relacl
        FROM  pg_class c_from
        WHERE c_from.oid  = dataset
        AND   c_to.oid    = overview_table;

      PERFORM _CDB_Add_Indexes(overview_table);

      -- TODO: If metadata about existing overviews is to be stored
      -- it should be done here (CDB_Overviews would consume such metadata)
    END IF;
  END
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

-- Dataset attributes (column names other than the
-- CartoDB primary key and geometry columns) which should be aggregated
-- in aggregated overviews.
-- Scope: private.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
-- Return value: set of attribute names
CREATE OR REPLACE FUNCTION _CDB_Aggregable_Attributes(reloid REGCLASS)
RETURNS SETOF information_schema.sql_identifier
AS $$
  SELECT c FROM CDB_ColumnNames(reloid) c, _CDB_Columns() cdb
    WHERE c NOT IN (
      cdb.pkey, cdb.geomcol, cdb.mercgeomcol
    )
$$ LANGUAGE SQL STABLE;

-- List of dataset attributes to be aggregated in aggregated overview
-- as a comma-separated SQL expression.
-- Scope: private.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
-- Return value: SQL subexpression as text
CREATE OR REPLACE FUNCTION _CDB_Aggregable_Attributes_Expression(reloid REGCLASS)
RETURNS TEXT
AS $$
DECLARE
  attr_list TEXT;
BEGIN
  SELECT string_agg(s.c, ',') FROM (
    SELECT * FROM _CDB_Aggregable_Attributes(reloid) c
  ) AS s INTO attr_list;

  RETURN attr_list;
END
$$ LANGUAGE PLPGSQL STABLE;

-- Check if a column of a table is of an unlimited-length text type
CREATE OR REPLACE FUNCTION _cdb_unlimited_text_column(reloid REGCLASS, col_name TEXT)
RETURNS BOOLEAN
AS $$
  SELECT EXISTS (
    SELECT a.attname
    FROM pg_class c
         LEFT JOIN pg_attribute a ON a.attrelid = c.oid
         LEFT JOIN pg_type t ON t.oid = a.atttypid
    WHERE c.oid = reloid
      AND a.attname = col_name
      AND format_type(a.atttypid, NULL) IN ('text', 'character varying', 'character')
      AND format_type(a.atttypid, NULL) = format_type(a.atttypid, a.atttypmod)
  );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION _cdb_categorical_column(reloid REGCLASS, col_name TEXT)
RETURNS BOOLEAN
AS $$
DECLARE
    schema_name TEXT;
    table_name TEXT;
    available BOOLEAN;
    categorical BOOLEAN;
BEGIN
    SELECT * FROM _cdb_split_table_name(reloid) INTO schema_name, table_name;
    SELECT n_distinct IS NOT NULL
    FROM pg_stats
    WHERE pg_stats.schemaname = schema_name
      AND pg_stats.tablename = table_name
      AND pg_stats.attname = col_name
    INTO available;
    IF available IS NULL OR NOT available THEN
      EXECUTE Format('ANALYZE %s;', reloid);
    END IF;
    SELECT n_distinct > 0 AND n_distinct <= 20
    FROM pg_stats
    WHERE pg_stats.schemaname = schema_name
      AND pg_stats.tablename = table_name
      AND pg_stats.attname = col_name
    INTO categorical;
    RETURN categorical;
END;
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE FUNCTION _cdb_mode_of_array(anyarray)
  RETURNS anyelement AS
$$
    SELECT a
    FROM unnest($1) a
    GROUP BY 1
    ORDER BY COUNT(1) DESC, 1
    LIMIT 1;
$$
LANGUAGE SQL IMMUTABLE;

DROP AGGREGATE IF EXISTS _cdb_mode(anyelement);
CREATE AGGREGATE _cdb_mode(anyelement) (
  SFUNC=array_append,
  STYPE=anyarray,
  FINALFUNC=_cdb_mode_of_array,
  INITCOND='{}'
);

-- SQL Aggregation expression for a datase attribute
-- Scope: private.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
--   column_name: column to be aggregated
--   table_alias: (optional) table qualifier for the column to be aggregated
-- Return SQL subexpression as text with aggregated attribute aliased
-- with its original name.
CREATE OR REPLACE FUNCTION _CDB_Attribute_Aggregation_Expression(reloid REGCLASS, column_name TEXT, table_alias TEXT DEFAULT '')
RETURNS TEXT
AS $$
DECLARE
  column_type TEXT;
  qualified_column TEXT;
  has_counter_column BOOLEAN;
  feature_count TEXT;
  total_feature_count TEXT;
  base_table REGCLASS;
BEGIN
  IF table_alias <> '' THEN
    qualified_column := Format('%I.%I', table_alias, column_name);
  ELSE
    qualified_column := Format('%I', column_name);
  END IF;

  column_type := CDB_ColumnType(reloid, column_name);

  SELECT EXISTS (
    SELECT * FROM CDB_ColumnNames(reloid)  as colname WHERE colname = '_feature_count'
  ) INTO has_counter_column;
  IF has_counter_column THEN
    feature_count := '_feature_count';
    total_feature_count := 'SUM(_feature_count)';
  ELSE
    feature_count := '1';
    total_feature_count := 'count(*)';
  END IF;

  base_table := _CDB_OverviewBaseTable(reloid);

  CASE column_type
  WHEN 'double precision', 'real', 'integer', 'bigint', 'numeric' THEN
    IF column_name = '_feature_count' THEN
      RETURN 'SUM(_feature_count)';
    ELSE
      IF column_type = 'integer' AND _cdb_categorical_column(base_table, column_name) THEN
        RETURN Format('CDB_Math_Mode(%s)::', qualified_column) || column_type;
      ELSE
        RETURN Format('SUM(%s*%s)/%s::' || column_type, qualified_column, feature_count, total_feature_count);
      END IF;
    END IF;
  WHEN 'text', 'character varying', 'character' THEN
    IF _cdb_categorical_column(base_table, column_name) THEN
      RETURN Format('_cdb_mode(%s)::', qualified_column) || column_type;
    ELSE
      IF _cdb_unlimited_text_column(base_table, column_name) THEN
        -- TODO: this should not be applied to columns containing largish text;
        -- it is intended only to short names/identifiers
        RETURN  'CASE WHEN count(distinct ' || qualified_column || ') = 1 THEN MIN(' || qualified_column || ') WHEN ' || total_feature_count || ' < 5 THEN string_agg(distinct ' || qualified_column || ','' / '') ELSE ''*'' END::' || column_type;
      ELSE
        RETURN 'CASE count(*) WHEN 1 THEN MIN(' || qualified_column || ') ELSE NULL END::' || column_type;
      END IF;
    END IF;
  WHEN 'boolean' THEN
    RETURN 'CASE count(*) WHEN 1 THEN BOOL_AND(' || qualified_column || ') ELSE NULL END::' || column_type;
  ELSE
    RETURN 'CASE count(*) WHEN 1 THEN MIN(' || qualified_column || ') ELSE NULL END::' || column_type;
  END CASE;
END
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- List of dataset aggregated attributes as a comma-separated SQL expression.
-- Scope: private.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
--   table_alias: (optional) table qualifier for the columns to be aggregated
-- Return value: SQL subexpression as text
CREATE OR REPLACE FUNCTION _CDB_Aggregated_Attributes_Expression(reloid REGCLASS, table_alias TEXT DEFAULT '')
RETURNS TEXT
AS $$
DECLARE
  attr_list TEXT;
BEGIN
  SELECT string_agg(_CDB_Attribute_Aggregation_Expression(reloid, s.c, table_alias) || Format(' AS %s', s.c), ',')
  FROM (
    SELECT * FROM _CDB_Aggregable_Attributes(reloid) c
  ) AS s INTO attr_list;

  RETURN attr_list;
END
$$ LANGUAGE PLPGSQL STABLE;

-- Array of geometry types detected in a cartodbfied table
-- For effciency only look at a limited number of rwos.
-- Parameters
--   reloid: oid of the input table. It must be a cartodbfy'ed table.
-- Return value: array of geometry type names
CREATE OR REPLACE FUNCTION _CDB_GeometryTypes(reloid REGCLASS)
RETURNS TEXT[]
AS $$
DECLARE
  gtypes TEXT[];
BEGIN
  EXECUTE Format('
    SELECT array_agg(DISTINCT ST_GeometryType(the_geom)) FROM (
      SELECT the_geom FROM %s
        WHERE (the_geom is not null) LIMIT 10
    ) as geom_types
  ', reloid)
  INTO gtypes;
  RETURN gtypes;
END
$$ LANGUAGE PLPGSQL STABLE;

-- Experimental Overview reduction method for point datasets.
-- It clusters the points using a grid, then aggregates the point in each
-- cluster into a point at the centroid of the clustered records.
-- Scope: private.
-- Parameters:
--   reloid original table (can be the base table of the dataset or an existing
--   overview) from which the overview is being generated.
--   ref_z Z level assigned to the original table
--   overview_z Z level of the overview to be generated, must be smaller than ref_z
-- Return value: Name of the generated overview table
CREATE OR REPLACE FUNCTION _CDB_GridCluster_Reduce_Strategy(reloid REGCLASS, ref_z INTEGER, overview_z INTEGER, grid_px FLOAT8 DEFAULT NULL)
RETURNS REGCLASS
AS $$
  DECLARE
    overview_rel TEXT;
    reduction FLOAT8;
    base_name TEXT;
    pixel_m FLOAT8;
    grid_m FLOAT8;
    offset_m FLOAT8;
    offset_x TEXT;
    offset_y TEXT;
    cell_x TEXT;
    cell_y TEXT;
    aggr_attributes TEXT;
    attributes TEXT;
    columns TEXT;
    gtypes TEXT[];
    schema_name TEXT;
    table_name TEXT;
    point_geom TEXT;
  BEGIN
    SELECT _CDB_GeometryTypes(reloid) INTO gtypes;
    IF gtypes IS NULL OR array_upper(gtypes, 1) <> 1 OR gtypes[1] <> 'ST_Point' THEN
      -- This strategy only supports datasets with point geomety
      RETURN NULL;
    END IF;

    --TODO: check applicability: geometry type, minimum number of points...

    overview_rel := _CDB_Overview_Name(reloid, ref_z, overview_z);

    -- Grid size in pixels at Z level overview_z
    IF grid_px IS NULL THEN
      grid_px := 1.0;
    END IF;

    SELECT * FROM _cdb_split_table_name(reloid) INTO schema_name, table_name;

    -- pixel_m: size of a pixel in webmercator units (meters)
    SELECT CDB_XYZ_Resolution(overview_z) INTO pixel_m;
    -- grid size in meters
    grid_m = grid_px * pixel_m;

    attributes := _CDB_Aggregable_Attributes_Expression(reloid);
    aggr_attributes := _CDB_Aggregated_Attributes_Expression(reloid);
    IF attributes <> '' THEN
      attributes := ', ' || attributes;
    END IF;
    IF aggr_attributes <> '' THEN
      aggr_attributes := aggr_attributes || ', ';
    END IF;

    -- Center of each cell:
    cell_x := Format('gx*%1$s + %2$s', grid_m, grid_m/2);
    cell_y := Format('gy*%1$s + %2$s', grid_m, grid_m/2);

    -- Displacement to the nearest pixel center:
    IF MOD(grid_px::numeric, 1.0::numeric) = 0 THEN
      offset_m := pixel_m/2 - MOD((grid_m/2)::numeric, pixel_m::numeric)::float8;
      offset_x := Format('%s', offset_m);
      offset_y := Format('%s', offset_m);
    ELSE
      offset_x := Format('%2$s/2 - MOD((%1$s)::numeric, (%2$s)::numeric)::float8', cell_x, pixel_m);
      offset_y := Format('%2$s/2 - MOD((%1$s)::numeric, (%2$s)::numeric)::float8', cell_y, pixel_m);
    END IF;

    point_geom := Format('ST_SetSRID(ST_MakePoint(%1$s + %3$s, %2$s + %4$s), 3857)', cell_x, cell_y, offset_x, offset_y);

    -- compute the resulting columns in the same order as in the base table
    WITH cols AS (
      SELECT
        CASE c
        WHEN 'cartodb_id' THEN 'cartodb_id'
        WHEN 'the_geom' THEN
          Format('ST_Transform(%s, 4326) AS the_geom', point_geom)
        WHEN 'the_geom_webmercator' THEN
           Format('%s AS the_geom_webmercator', point_geom)
        ELSE c
        END AS column
        FROM CDB_ColumnNames(reloid) c
    )
    SELECT string_agg(s.column, ',') FROM (
      SELECT * FROM cols
    ) AS s INTO columns;

    IF NOT columns LIKE '%_feature_count%' THEN
      columns := columns || ', n AS _feature_count';
    END IF;

    EXECUTE Format('DROP TABLE IF EXISTS %I.%I CASCADE;', schema_name, overview_rel);

    -- Now we cluster the data using a grid of size grid_m
    -- and selecte the centroid (average coordinates) of each cluster.
    -- If we had a selected numeric attribute of interest we could use it
    -- as a weight for the average coordinates.
    EXECUTE Format('
      CREATE TABLE %7$I.%3$I AS
         WITH clusters AS (
           SELECT
             %5$s
             count(*) AS n,
             Floor(ST_X(f.the_geom_webmercator)/%2$s)::int AS gx,
             Floor(ST_Y(f.the_geom_webmercator)/%2$s)::int AS gy,
             MIN(cartodb_id) AS cartodb_id
          FROM %1$s f
          GROUP BY gx, gy
         )
         SELECT %6$s FROM clusters
    ', reloid::text, grid_m, overview_rel, attributes, aggr_attributes, columns, schema_name);

    RETURN Format('%I.%I', schema_name, overview_rel)::regclass;
  END;
$$ LANGUAGE PLPGSQL;

-- Create overview tables for a dataset.
-- Scope: public
-- Parameters:
--   reloid: oid of the input table. It must be a cartodbfy'ed table with
--           vector features.
--   refscale_strategy: function that computes the reference Z of the dataset
--   reduce_strategy: function that generates overviews from a base table
--                    or higher level overview. The overview tables
--                    created by the strategy must have the same columns
--                    as the base table and in the same order.
-- Return value: Array with the names of the generated overview tables
CREATE OR REPLACE FUNCTION CDB_CreateOverviews(reloid REGCLASS, refscale_strategy regproc DEFAULT '_CDB_Feature_Density_Ref_Z_Strategy(REGCLASS,FLOAT8)'::regprocedure, reduce_strategy regproc DEFAULT '_CDB_GridCluster_Reduce_Strategy(REGCLASS,INTEGER,INTEGER,FLOAT8)'::regprocedure)
RETURNS text[]
AS $$
DECLARE
  tolerance_px FLOAT8;
BEGIN
  -- Use the default tolerance
  tolerance_px := 1.0;
  RETURN CDB_CreateOverviewsWithToleranceInPixels(reloid, tolerance_px, refscale_strategy, reduce_strategy);
END;
$$ LANGUAGE PLPGSQL;

-- Create overviews with additional parameter to define the desired detail/tolerance in pixels
CREATE OR REPLACE FUNCTION CDB_CreateOverviewsWithToleranceInPixels(reloid REGCLASS, tolerance_px FLOAT8, refscale_strategy regproc DEFAULT '_CDB_Feature_Density_Ref_Z_Strategy(REGCLASS,FLOAT8)'::regprocedure, reduce_strategy regproc DEFAULT  '_CDB_GridCluster_Reduce_Strategy(REGCLASS,INTEGER,INTEGER,FLOAT8)'::regprocedure)
RETURNS text[]
AS $$
DECLARE
  ref_z integer;
  overviews_z integer[];
  base_z integer;
  base_rel REGCLASS;
  overview_z integer;
  overview_tables REGCLASS[];
  overviews_step integer := 1;
  has_counter_column boolean;
BEGIN
  -- Determine the referece zoom level
  EXECUTE 'SELECT ' || quote_ident(refscale_strategy::text) || Format('(''%s'', %s);', reloid, tolerance_px) INTO ref_z;

  IF ref_z < 0 OR ref_z IS NULL THEN
    RETURN NULL;
  END IF;

  -- Determine overlay zoom levels
  -- TODO: should be handled by the refscale_strategy?
  overview_z := ref_z - 1;
  WHILE overview_z >= 0 LOOP
    SELECT array_append(overviews_z, overview_z) INTO overviews_z;
    overview_z := overview_z - overviews_step;
  END LOOP;

  -- Create overlay tables
  base_z := ref_z;
  base_rel := reloid;
  FOREACH overview_z IN ARRAY overviews_z LOOP
    EXECUTE 'SELECT ' || quote_ident(reduce_strategy::text) || Format('(''%s'', %s, %s, %s);', base_rel, base_z, overview_z, tolerance_px) INTO base_rel;
    IF base_rel IS NULL THEN
      EXIT;
    END IF;
    base_z := overview_z;
    PERFORM _CDB_Register_Overview(reloid, base_rel, base_z);
    SELECT array_append(overview_tables, base_rel) INTO overview_tables;
  END LOOP;

  IF overview_tables IS NOT NULL AND array_length(overview_tables, 1) > 0 THEN
    SELECT EXISTS (
      SELECT * FROM CDB_ColumnNames(reloid)  as colname WHERE colname = '_feature_count'
    ) INTO has_counter_column;
    IF NOT has_counter_column THEN
      EXECUTE Format('
        ALTER TABLE %s ADD COLUMN _feature_count integer DEFAULT 1;
      ', reloid);
    END IF;
  END IF;

  RETURN overview_tables;
END;
$$ LANGUAGE PLPGSQL;

-- Here are some older signatures of these functions, no longar in use.
-- They must be droped here, after the (new) definition of the function `CDB_CreateOverviews`
-- because that function used to contain references to them in the default argument values.
DROP FUNCTION IF EXISTS _CDB_Feature_Density_Ref_Z_Strategy(REGCLASS);
DROP FUNCTION IF EXISTS _CDB_GridCluster_Reduce_Strategy(REGCLASS,INTEGER,INTEGER);
DROP FUNCTION IF EXISTS _CDB_Sampling_Reduce_Strategy(REGCLASS,INTEGER,INTEGER);
