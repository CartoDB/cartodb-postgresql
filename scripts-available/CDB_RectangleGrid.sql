-- In older versions of the extension, CDB_RectangleGrid had a different signature
DROP FUNCTION IF EXISTS @extschema@.CDB_RectangleGrid(GEOMETRY, FLOAT8, FLOAT8, GEOMETRY);

--
-- Fill given extent with a rectangular coverage
--
-- @param ext Extent to fill. Only rectangles with center point falling
--            inside the extent (or at the lower or leftmost edge) will
--            be emitted. The returned hexagons will have the same SRID
--            as this extent.
--
-- @param width Width of each rectangle
--
-- @param height Height of each rectangle
--
-- @param origin Optional origin to allow for exact tiling.
--               If omitted the origin will be 0,0.
--               The parameter is checked for having the same SRID
--               as the extent.
--
-- @param maxcells Optional maximum number of grid cells to generate;
--                 if the grid requires more cells to cover the extent
--                 and exception will occur.
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_RectangleGrid(ext GEOMETRY, width FLOAT8, height FLOAT8, origin GEOMETRY DEFAULT NULL, maxcells INTEGER DEFAULT 512*512)
RETURNS SETOF GEOMETRY
AS $$
DECLARE
  h GEOMETRY; -- rectangle cell
  hstep FLOAT8; -- horizontal step
  vstep FLOAT8; -- vertical step
  hw FLOAT8; -- half width
  hh FLOAT8; -- half height
  vstart FLOAT8;
  hstart FLOAT8;
  hend FLOAT8;
  vend FLOAT8;
  xoff FLOAT8;
  yoff FLOAT8;
  xgrd FLOAT8;
  ygrd FLOAT8;
  x FLOAT8;
  y FLOAT8;
  srid INTEGER;
BEGIN

  srid := @postgisschema@.ST_SRID(ext);

  xoff := 0; 
  yoff := 0;

  IF origin IS NOT NULL THEN
    IF @postgisschema@.ST_SRID(origin) != srid THEN
      RAISE EXCEPTION 'SRID mismatch between extent (%) and origin (%)', srid, ST_SRID(origin);
    END IF;
    xoff := @postgisschema@.ST_X(origin);
    yoff := @postgisschema@.ST_Y(origin);
  END IF;

  --RAISE DEBUG 'X offset: %', xoff;
  --RAISE DEBUG 'Y offset: %', yoff;

  hw := width/2.0;
  hh := height/2.0;

  xgrd := hw;
  ygrd := hh;
  --RAISE DEBUG 'X grid size: %', xgrd;
  --RAISE DEBUG 'Y grid size: %', ygrd;

  hstep := width;
  vstep := height;

  -- Tweak horizontal start on hstep grid from origin 
  hstart := xoff + ceil((@postgisschema@.ST_XMin(ext)-xoff)/hstep)*hstep; 
  --RAISE DEBUG 'hstart: %', hstart;

  -- Tweak vertical start on vstep grid from origin 
  vstart := yoff + ceil((@postgisschema@.ST_Ymin(ext)-yoff)/vstep)*vstep; 
  --RAISE DEBUG 'vstart: %', vstart;

  hend := ST_XMax(ext);
  vend := ST_YMax(ext);

  --RAISE DEBUG 'hend: %', hend;
  --RAISE DEBUG 'vend: %', vend;

  If maxcells IS NOT NULL AND maxcells > 0 THEN
    IF ((hend - hstart)/hstep * (vend - vstart)/vstep)::integer > maxcells THEN
        RAISE EXCEPTION 'The requested grid is too big to be rendered';
    END IF;
  END IF;

  x := hstart;
  WHILE x < hend LOOP -- over X
    y := vstart;
    h := @postgisschema@.ST_MakeEnvelope(x-hw, y-hh, x+hw, y+hh, srid);
    WHILE y < vend LOOP -- over Y
      RETURN NEXT h;
      h := @postgisschema@.ST_Translate(h, 0, vstep);
      y := yoff + round(((y + vstep)-yoff)/ygrd)*ygrd; -- round to grid
    END LOOP;
    x := xoff + round(((x + hstep)-xoff)/xgrd)*xgrd; -- round to grid
  END LOOP;

  RETURN;
END
$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
