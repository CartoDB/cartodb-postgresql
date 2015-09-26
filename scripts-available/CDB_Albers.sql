
--  Convert your states (or other geometries id'd by state) to 
--    display as with Alaska, Hawaii, and Puerto Rico transcaled
--
--  @param g: input geometry
--  @param state: column identifying the state (name, postal abbreviation, state FP)
--  
--  output: geometries of states in albers projections of the states
-- 
-- Projections:
--		- Lower 48 states: http://spatialreference.org/ref/sr-org/7965/
-- 		- Alaska: http://spatialreference.org/ref/epsg/3338/
--		- Puerto Rico: http://www.spatialreference.org/ref/epsg/nad83-puerto-rico-virgin-is/
--		- Hawaii: http://epsg.io/102007


CREATE OR REPLACE FUNCTION CDB_Albers50 (g geometry, state text) RETURNS geometry as $$
DECLARE
	reply geometry;
	srid INT;
	alaska text[] = '{"Alaska","AK","02"}'::text[];
	hawaii text[] = '{"Hawaii","HI","15"}'::text[];
	puertorico text[] = '{"Puerto Rico","PR","72"}'::text[];
BEGIN
	
	-- convert to wgs84
	IF ST_SRID(g) != 4326 THEN g = ST_Transform(g,4326); END IF;

	EXECUTE 'SELECT
	    ST_SetSRID(
	    	CASE 
  				WHEN $2 = any($3)
					ST_Scale(
						ST_Translate(
							ST_Transform(
								the_geom
								, 3338
							)
							, -3800000
							, -900000
						)
						, 0.7
						, 0.7
					)
				WHEN $2 = any($4)
					THEN 
  					ST_Scale(
  						ST_Transform(
  							ST_Translate(
  								$1
			                    , -8
			                    , -5
			                )
			                , 102007
			            )
			            , 1.2
			            , 1.2
			        )
				WHEN $2 = any($5)
					THEN 
  					ST_Scale(
  						ST_Transform(
  							ST_Translate(
  								$1
			                    , 10
			                    , -1.5
			                )
			                , 32161
						)
						, 1.5
						, 1.5
					)
				ELSE
					ST_Transform($1,42303)
  				END
  				, 4326
  			)'
	INTO reply
	USING g, state, alaska, hawaii, puertorico;

	RETURN reply;

END; 
$$ language plpgsql IMMUTABLE;
