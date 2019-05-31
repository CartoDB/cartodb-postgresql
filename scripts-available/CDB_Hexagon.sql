-- Return an Hexagon with given center and side (or maximal radius)
CREATE OR REPLACE FUNCTION @extschema@.CDB_MakeHexagon(center GEOMETRY, radius FLOAT8)
RETURNS GEOMETRY
AS $$
  SELECT @postgisschema@.ST_MakePolygon(@postgisschema@.ST_MakeLine(geom))
    FROM
    (
      SELECT (@postgisschema@.ST_DumpPoints(@postgisschema@.ST_ExteriorRing(@postgisschema@.ST_Buffer($1, $2, 3)))).*
    ) as points
    WHERE path[1] % 2 != 0
$$ LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;


-- In older versions of the extension, CDB_HexagonGrid had a different signature
DROP FUNCTION IF EXISTS @extschema@.CDB_HexagonGrid(GEOMETRY, FLOAT8, GEOMETRY);

--
-- Fill given extent with an hexagonal coverage
--
-- @param ext Extent to fill. Only hexagons with center point falling
--            inside the extent (or at the lower or leftmost edge) will
--            be emitted. The returned hexagons will have the same SRID
--            as this extent.
--
-- @param side Side measure for the hexagon.
--             Maximum diameter will be 2 * side.
--
-- @param origin Optional origin to allow for exact tiling.
--               If omitted the origin will be 0,0.
--               The parameter is checked for having the same SRID
--               as the extent.
--
-- @param maxcells Optional maximum number of grid cells to generate;
--                 if the grid requires more cells to cover the extent
--                 and exception will occur.
----
-- DROP FUNCTION IF EXISTS CDB_HexagonGrid(ext GEOMETRY, side FLOAT8);
CREATE OR REPLACE FUNCTION @extschema@.CDB_HexagonGrid(ext GEOMETRY, side FLOAT8, origin GEOMETRY DEFAULT NULL, maxcells INTEGER DEFAULT 512*512)
RETURNS SETOF GEOMETRY
AS $$
DECLARE
  h GEOMETRY; -- hexagon
  c GEOMETRY; -- center point
  rec RECORD;
  hstep FLOAT8; -- horizontal step
  vstep FLOAT8; -- vertical step
  vstart FLOAT8;
  vstartary FLOAT8[];
  vstartidx INTEGER;
  hskip BIGINT;
  hstart FLOAT8;
  hend FLOAT8;
  vend FLOAT8;
  xoff FLOAT8;
  yoff FLOAT8;
  xgrd FLOAT8;
  ygrd FLOAT8;
  srid INTEGER;
BEGIN

  --            |     |     
  --            |hstep|
  --  ______   ___    |    
  --  vstep  /     \ ___ /
  --  ______ \ ___ /     \  
  --         /     \ ___ / 
  --
  --
  RAISE DEBUG 'Side: %', side;

  vstep := side * sqrt(3); -- x 2 ?
  hstep := side * 1.5;

  RAISE DEBUG 'vstep: %', vstep;
  RAISE DEBUG 'hstep: %', hstep;

  srid := ST_SRID(ext);

  xoff := 0; 
  yoff := 0;

  IF origin IS NOT NULL THEN
    IF @postgisschema@.ST_SRID(origin) != srid THEN
      RAISE EXCEPTION 'SRID mismatch between extent (%) and origin (%)', srid, ST_SRID(origin);
    END IF;
    xoff := @postgisschema@.ST_X(origin);
    yoff := @postgisschema@.ST_Y(origin);
  END IF;

  RAISE DEBUG 'X offset: %', xoff;
  RAISE DEBUG 'Y offset: %', yoff;

  xgrd := side * 0.5;
  ygrd := ( side * sqrt(3) ) / 2.0;
  RAISE DEBUG 'X grid size: %', xgrd;
  RAISE DEBUG 'Y grid size: %', ygrd;

  -- Tweak horizontal start on hstep*2 grid from origin 
  hskip := ceil((@postgisschema@.ST_XMin(ext)-xoff)/hstep);
  RAISE DEBUG 'hskip: %', hskip;
  hstart := xoff + hskip*hstep;
  RAISE DEBUG 'hstart: %', hstart;

  -- Tweak vertical start on hstep grid from origin 
  vstart := yoff + ceil((@postgisschema@.ST_Ymin(ext)-yoff)/vstep)*vstep; 
  RAISE DEBUG 'vstart: %', vstart;

  hend := @postgisschema@.ST_XMax(ext);
  vend := @postgisschema@.ST_YMax(ext);

  IF vstart - (vstep/2.0) < @postgisschema@.ST_YMin(ext) THEN
    vstartary := ARRAY[ vstart + (vstep/2.0), vstart ];
  ELSE
    vstartary := ARRAY[ vstart - (vstep/2.0), vstart ];
  END IF;

  If maxcells IS NOT NULL AND maxcells > 0 THEN
    IF CEIL((CEIL((vend-vstart)/(vstep/2.0)) * CEIL((hend-hstart)/(hstep*2.0/3.0)))/3.0)::integer > maxcells THEN
      RAISE EXCEPTION 'The requested grid is too big to be rendered';
    END IF;
  END IF;

  vstartidx := abs(hskip)%2;

  RAISE DEBUG 'vstartary: % : %', vstartary[1], vstartary[2];
  RAISE DEBUG 'vstartidx: %', vstartidx;

  c := @postgisschema@.ST_SetSRID(@postgisschema@.ST_MakePoint(hstart, vstartary[vstartidx+1]), srid);
  h := @postgisschema@.ST_SnapToGrid(@extschema@.CDB_MakeHexagon(c, side), xoff, yoff, xgrd, ygrd);
  vstartidx := (vstartidx + 1) % 2;
  WHILE @postgisschema@.ST_X(c) < hend LOOP -- over X
    --RAISE DEBUG 'X loop starts, center point: %', ST_AsText(c);
    WHILE @postgisschema@.ST_Y(c) < vend LOOP -- over Y
      --RAISE DEBUG 'Center: %', ST_AsText(c);
      --h := ST_SnapToGrid(CDB_MakeHexagon(c, side), xoff, yoff, xgrd, ygrd);
      RETURN NEXT h;
      h := @postgisschema@.ST_SnapToGrid(ST_Translate(h, 0, vstep), xoff, yoff, xgrd, ygrd);
      c := @postgisschema@.ST_Translate(c, 0, vstep);  -- TODO: drop ?
    END LOOP;
    -- TODO: translate h direcly ...
    c := @postgisschema@.ST_SetSRID(@postgisschema@.ST_MakePoint(ST_X(c)+hstep, vstartary[vstartidx+1]), srid);
    h := @postgisschema@.ST_SnapToGrid(@extschema@.CDB_MakeHexagon(c, side), xoff, yoff, xgrd, ygrd);
    vstartidx := (vstartidx + 1) % 2;
  END LOOP;

  RETURN;
END
$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
