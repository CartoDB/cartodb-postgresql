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
      'SELECT ST_EstimatedExtent(''%1$I'', ''%2$I'', ''%3$I'');',
      table_id.schema_name, table_id.table_name, 'the_geom_webmercator'
    );

    BEGIN
      EXECUTE ext_query INTO ext;
      EXCEPTION
        -- This is the typical ERROR: stats for "mytable" do not exist
        WHEN internal_error THEN
          -- Get stats and execute again
          EXECUTE format('ANALYZE %1$I', reloid);
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
        SELECT (-floor(log(2, (greatest(ST_XMax(ext.g)-ST_XMin(ext.g), ST_YMax(ext.g)-ST_YMin(ext.g))/(%4$s*%5$s))::numeric)))::integer z
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
      WHERE t.e > %2$s AND t.z < (base.z + %3$s)
    )
    SELECT MAX(e/ST_Area(CDB_XYZ_Extent(x,y,z))) FROM t where e > 0;
  ', reloid::text, min_features, nz, n, c, reloid::oid)
  INTO fd;
  RETURN fd;
  END
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION _CDB_Dummy_Ref_Z_Strategy(reloid REGCLASS)
RETURNS INTEGER
AS $$
  DECLARE
    lim FLOAT8 := 500; -- TODO: determine/parameterize this
    nz integer := 4;
    fd FLOAT8;
    c FLOAT8;
  BEGIN
    -- Compute fd as an estimation of the (maximum) number
    -- of features per unit of tile area (in webmercator squared meters)
    SELECT _CDB_Feature_Density(reloid, nz) INTO fd;
    -- lim maximum number of (desiderable) features per tile
    -- we have c = 2*Pi*R = CDB_XYZ_Resolution(-8) (earth circumference)
    -- ta(z): tile area = power(c*power(2,z), 2) = c*c*power(2,2*z)
    -- => fd*ta(z) if the average number of features per tile at level z
    -- find minimum z so that fd*ta(z) <= lim
    -- compute a rough 'feature density' value
    SELECT CDB_XYZ_Resolution(-8) INTO c;
    RETURN ceil(log(2.0, (c*c*fd/lim)::numeric)/2);
  END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION _CDB_Overview_Name(ref REGCLASS, ref_z INTEGER, overview_z INTEGER)
RETURNS TEXT
AS $$
  DECLARE
    base TEXT;
    suffix TEXT;
    is_overview BOOLEAN;
  BEGIN
    suffix := Format('_ov%s', ref_z);
    SELECT ref::text LIKE Format('%%%s', suffix) INTO is_overview;
    IF is_overview THEN
      SELECT substring(ref::text FROM 1 FOR length(ref::text)-length(suffix)) INTO base;
    ELSE
      base := ref;
    END IF;
    RETURN Format('%s_ov%s', base::text, overview_z);
  END
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION _CDB_Dummy_Reduce_Strategy(reloid REGCLASS, ref_z INTEGER, overview_z INTEGER)
RETURNS REGCLASS
AS $$
  DECLARE
    overview_rel TEXT;
    reduction FLOAT8;
    base_name TEXT;
  BEGIN
    overview_rel := _CDB_Overview_Name(reloid, ref_z, overview_z);
    -- TODO: implement a proper reduction technique.
    -- Here we're just inefficiently sampling the data to mantain
    -- the approximate visual density of the reference level.
    reduction := power(2, 2*(overview_z - ref_z));
    EXECUTE Format('DROP TABLE IF EXISTS %s CASCADE;', overview_rel);
    EXECUTE Format('CREATE TABLE %s AS SELECT * FROM %s WHERE random() < %s;', overview_rel, reloid, reduction);
    RETURN overview_rel;
  END;
$$ LANGUAGE PLPGSQL;

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
  SELECT c FROM cartodb.CDB_ColumnNames(reloid) c, _CDB_Columns() cdb
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
BEGIN
  IF table_alias <> '' THEN
    qualified_column := Format('%I.%I', table_alias, column_name);
  ELSE
    qualified_column := Format('%I', column_name);
  END IF;

  column_type := cartodb.CDB_ColumnType(reloid, column_name);

  CASE column_type
  WHEN 'double precision', 'real', 'integer', 'bigint' THEN
    RETURN Format('AVG(%s)::' || column_type, qualified_column);
  WHEN 'text' THEN
    -- TODO: we could define a new aggregate function that returns distinct
    -- separated values with a limit, adding ellipsis if more values existed
    -- e.g. with '/' as separator and a limit of three:
    --     'A', 'B', 'A', 'C', 'D' => 'A/B/C/...'
    -- Other ideas: if value is unique then use it, otherwise use something
    -- like '*' or '(varies)' or '(multiple values)', or NULL
    RETURN '''''::' || column_type;
  ELSE RETURN 'NULL::' || column_type;
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

CREATE OR REPLACE FUNCTION _CDB_GridCluster_Reduce_Strategy(reloid REGCLASS, ref_z INTEGER, overview_z INTEGER)
RETURNS REGCLASS
AS $$
  DECLARE
    overview_rel TEXT;
    reduction FLOAT8;
    base_name TEXT;
    grid_px FLOAT8 = 7.5; -- Grid size in pixels at Z level overview_z
    grid_m FLOAT8;
    aggr_attributes TEXT;
    attributes TEXT;
  BEGIN
    overview_rel := _CDB_Overview_Name(reloid, ref_z, overview_z);

    -- compute grid cell size using the overview_z dimension...
    SELECT CDB_XYZ_Resolution(overview_z)*grid_px INTO grid_m;

    attributes := _CDB_Aggregable_Attributes_Expression(reloid);
    aggr_attributes := _CDB_Aggregated_Attributes_Expression(reloid);
    IF attributes <> '' THEN
      attributes := attributes || ', ';
    END IF;
    IF aggr_attributes <> '' THEN
      aggr_attributes := aggr_attributes || ', ';
    END IF;

    EXECUTE Format('DROP TABLE IF EXISTS %s CASCADE;', overview_rel);

    -- Now we cluster the data using a grid of size grid_m
    -- and selecte the centroid (average coordinates) of each cluster.
    -- If we had a selected numeric attribute of interest we could use it
    -- as a weight for the average coordinates.
    EXECUTE Format('
      CREATE TABLE %3$s AS
         WITH clusters AS (
           SELECT
             %5$s
             count(*) AS n,
             SUM(ST_X(f.the_geom_webmercator)) AS sx,
             SUM(ST_Y(f.the_geom_webmercator)) AS sy,
             Floor(ST_X(f.the_geom_webmercator)/%2$s)::int AS gx,
             Floor(ST_Y(f.the_geom_webmercator)/%2$s)::int AS gy,
             row_number() OVER () AS cartodb_id
          FROM %1$s f
          GROUP BY gx, gy
         )
         SELECT
           %4$s
           cartodb_id,
           ST_SetSRID(ST_MakePoint(sx/n, sy/n), 3857) AS the_geom_webmercator,
           ST_Transform(ST_SetSRID(ST_MakePoint(sx/n, sy/n), 3857), 4326) AS the_geom
         FROM clusters
    ', reloid::text, grid_m, overview_rel, attributes, aggr_attributes);

    RETURN overview_rel;
  END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION CDB_CreateOverviews(
  reloid REGCLASS,
  refscale_strategy regproc DEFAULT '_CDB_Dummy_Ref_Z_Strategy'::regproc,
  reduce_strategy   regproc DEFAULT '_CDB_Dummy_Reduce_Strategy'::regproc
)
RETURNS text[]
AS $$
DECLARE
  ref_z integer;
  overviews_z integer[];
  base_z integer;
  base_rel REGCLASS;
  overview_z integer;
  overview_tables REGCLASS[];
BEGIN
  -- Determine the referece zoom level
  EXECUTE 'SELECT ' || quote_ident(refscale_strategy::text) || Format('(''%s'');', reloid) INTO ref_z;

  -- Determine overlay zoom levels
  -- TODO: should be handled by the refscale_stragegy?
  overview_z := ref_z - 1;
  WHILE overview_z >= 0 LOOP
    SELECT array_append(overviews_z, overview_z) INTO overviews_z;
    overview_z := overview_z - 2;
  END LOOP;

  -- Create overlay tables
  base_z := ref_z;
  base_rel := reloid;
  FOREACH overview_z IN ARRAY overviews_z LOOP
    EXECUTE 'SELECT ' || quote_ident(reduce_strategy::text) || Format('(''%s'', %s, %s);', base_rel, base_z, overview_z) INTO base_rel;
    base_z := overview_z;
    SELECT array_append(overview_tables, base_rel) INTO overview_tables;
  END LOOP;

  -- TODO: we'll need to store metadata somewhere to define
  -- which overlay levels are available.

  RETURN overview_tables;
END;
$$ LANGUAGE PLPGSQL;
