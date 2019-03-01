-- Great circle point-to-point routes, based on:
--   http://blog.cartodb.com/jets-and-datelines/
--
CREATE OR REPLACE FUNCTION CDB_GreatCircle(start_point geometry, end_point geometry, max_segment_length NUMERIC DEFAULT 100000)
RETURNS geometry AS $$
DECLARE
  line geometry;
BEGIN
  line = ST_Segmentize(
    ST_Makeline(
      start_point,
      end_point
    )::geography,
    max_segment_length
  )::geometry;

  IF ST_XMax(line) - ST_XMin(line) > 180 THEN
    line = ST_Difference(
      ST_ShiftLongitude(line),
			ST_Buffer(ST_GeomFromText('LINESTRING(180 90, 180 -90)', 4326), 0.00001)
		);
  END IF;
RETURN line;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
