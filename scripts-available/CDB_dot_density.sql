--
-- Creates N points randomly distributed arround the polygon
--
-- @param g - the geometry to be turned in to points
--
-- @param no_points - the number of points to generate
--
-- @params max_iter_per_point - the function generates points in the polygon's bounding box
-- and discards points which don't lie in the polygon. max_iter_per_point specifies how many
-- misses per point the funciton accepts before giving up.
--
-- Returns: Multipoint with the requested points


CREATE OR REPLACE FUNCTION CDB_dot_density(g geometry , no_points Integer, max_iter_per_point Integer DEFAULT 1000 )
RETURNS geometry AS $$
DECLARE
  extent GEOMETRY;
  test_point Geometry;
  width                NUMERIC;
  height               NUMERIC;
  x0                   NUMERIC;
  y0                   NUMERIC;
  xp                   NUMERIC;
  yp                   NUMERIC;
	no_left              INTEGER;
  remaining_iterations INTEGER;
  points               GEOMETRY[];
BEGIN
  extent  := ST_Envelope(g);
  width   := ST_XMax(extent) - ST_XMIN(extent);
  height  := ST_YMax(extent) - ST_YMIN(extent);
  x0 	  := ST_XMin(extent);
  y0 	  := ST_YMin(extent);
  no_left := no_points;
  remaining_iterations := no_points*max_iter_per_point;

  LOOP
    if(no_left=0) THEN
      EXIT;
    END IF;

    if(remaining_iterations = 0 ) THEN
      RAISE 'hit_max_point_iterations';
    END IF;

    xp = x0 + width*random();
    yp = y0 + height*random();
    test_point = CDB_LATLNG(yp,xp);

    IF(ST_Contains(g, test_point)) THEN
      no_left = no_left - 1;
      points := points || test_point;
    else
      remaining_iterations = remaining_iterations -1;
    END IF;
  END LOOP;
  RETURN ST_Collect(points);
END;
$$
LANGUAGE plpgsql VOLATILE;
