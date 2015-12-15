
CREATE OR REPLACE FUNCTION _CDB_Dummy_Ref_Z_Strategy(reloid REGCLASS)
RETURNS INTEGER
AS $$
  DECLARE
    lim FLOAT8 := 1000; -- TODO: determine/parameterize this
    fd FLOAT8;
    c FLOAT8;
  BEGIN
    -- lim maximum number of (desiderable) features per tile
    -- we have c = 2*Pi*R = CDB_XYZ_Resolution(-8) (earth circumference)
    -- fd: feature density: number of features per unit of area (count(*)/ST_Area())
    -- ta(z): tile area = power(c*power(2,z), 2) = c*c*power(2,2*z)
    -- => fd*ta(z) if the average number of features per tile at level z
    -- find minimum z so that fd*ta(z) <= lim
    -- compute a rough 'feature density' value
    EXECUTE 'SELECT Count(*)/ST_Area(ST_Extent(the_geom_webmercator)) FROM ' || reloid::text || ';' INTO fd;
    -- TODO: estimate the features per *area* value in some efficient manner
    -- that samples various areas of the dataset extents.
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
    suffix := Format('_ov%', ref_z);
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
