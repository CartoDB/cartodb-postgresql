-- Great circle point-to-point routes, based on:
--   http://blog.cartodb.com/jets-and-datelines/
--
CREATE OR REPLACE FUNCTION @extschema@.CDB_GreatCircle(start_point @postgisschema@.geometry, end_point @postgisschema@.geometry, max_segment_length NUMERIC DEFAULT 100000)
RETURNS @postgisschema@.geometry AS $$
DECLARE
  line @postgisschema@.geometry;
BEGIN
  line = @postgisschema@.ST_Segmentize(
    @postgisschema@.ST_Makeline(
      start_point,
      end_point
    )::geography,
    max_segment_length
  )::geometry;

  IF @postgisschema@.ST_XMax(line) - @postgisschema@.ST_XMin(line) > 180 THEN
    line = @postgisschema@.ST_Difference(
      @postgisschema@.ST_ShiftLongitude(line),
			@postgisschema@.ST_Buffer(@postgisschema@.ST_GeomFromText('LINESTRING(180 90, 180 -90)', 4326), 0.00001)
		);
  END IF;
RETURN line;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
