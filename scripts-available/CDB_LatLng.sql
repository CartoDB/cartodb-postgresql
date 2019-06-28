--
-- Create a valid GEOMETRY in 4326 from a lat/lng pair
--
-- @param lat A numeric latitude value.
--
-- @param lng A numeric longitude value.
--  
--

CREATE OR REPLACE FUNCTION @extschema@.CDB_LatLng (lat NUMERIC, lng NUMERIC) RETURNS @postgisschema@.geometry as $$ 
    SELECT @postgisschema@.ST_SetSRID(@postgisschema@.ST_MakePoint(lng,lat), 4326);
$$ language SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION @extschema@.CDB_LatLng (lat FLOAT8, lng FLOAT8) RETURNS @postgisschema@.geometry as $$
    SELECT @postgisschema@.ST_SetSRID(@postgisschema@.ST_MakePoint(lng,lat), 4326);
$$ language SQL IMMUTABLE PARALLEL SAFE;

