create or replace function CDB_GreatCircle(start_point geometry ,end_point geometry ) RETURNS geometry as
$$
DECLARE
	line geometry;
BEGIN

line = ST_Segmentize(
         ST_Makeline(
           start_point,
           end_point
         )::geography,
         100000
     )::geometry;

if ST_XMax(line) - ST_XMin(line) > 180 then

	line = ST_Difference(
    ST_Shift_Longitude(line), ST_Buffer(ST_GeomFromText('LINESTRING(180 90, 180 -90)',4326), 0.00001));
end if;


return line;

END; $$
LANGUAGE 'plpgsql';
