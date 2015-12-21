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
      WITH ext AS (SELECT ST_Extent(the_geom_webmercator) g FROM %1$s),
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
  ', reloid::text, min_features, nz, n, c)
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

CREATE OR REPLACE FUNCTION _CDB_GridCluster_Reduce_Strategy(reloid REGCLASS, ref_z INTEGER, overview_z INTEGER)
RETURNS REGCLASS
AS $$
  DECLARE
    overview_rel TEXT;
    reduction FLOAT8;
    base_name TEXT;
    grid_px FLOAT8 = 3.0;
    grid_m FLOAT8;
    aggr_attributes TEXT;
    attributes TEXT;
  BEGIN
    overview_rel := _CDB_Overview_Name(reloid, ref_z, overview_z);

    -- compute grid cell size using the overview_z dimension...
    SELECT CDB_XYZ_Resolution(overview_z)*grid_px INTO grid_m;

    -- TODO: compute expression to aggregate attributes of the table
    -- aggr_attributes = 'num_attr1, ...''
    -- aggr_attributes = 'AVG(num_attr1) num_attr1, ...''
    -- for text attributes we can use NULL or something like '*varies*'
    attributes := '';
    aggr_attributes := '';

    EXECUTE Format('DROP TABLE IF EXISTS %s CASCADE;', overview_rel);

    EXECUTE Format('
      CREATE TABLE %3$s AS
         WITH clusters AS (
           SELECT
             first_value(f.cartodb_id) OVER (
               PARTITION BY
                 ST_SnapToGrid(f.the_geom_webmercator, 0, 0, %2$s, %2$s)
             ) AS cartodb_id,
             %4$s
             the_geom,
             the_geom_webmercator
             FROM %1$s f
         )
         SELECT
           cartodb_id,
           ST_Centroid(ST_Collect(clusters.the_geom)) AS the_geom,
           %5$s
           ST_Centroid(ST_Collect(clusters.the_geom_webmercator)) AS the_geom_webmercator
         FROM clusters
         GROUP BY cartodb_id;
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
