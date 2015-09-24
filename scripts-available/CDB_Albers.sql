
--  Convert your states (or other geometries id'd by state) to 
--    display as an albers projection
--  Andy Eschbacher, 09/2015
--
--  @param g: input geometry
--  @param state: column identifying the state (name, abbreviation, FP)
--  
--  output: geometries of states in albers projections of the states
-- 
-- Projections:
-- 		- 
--		- Puerto Rico: http://www.spatialreference.org/ref/epsg/nad83-puerto-rico-virgin-is/
--		- Hawaii: http://epsg.io/102007


CREATE OR REPLACE FUNCTION CDB_AlbersUSA (g geometry, state text, srid numeric DEFAULT 3857) RETURNS geometry as $$ 
DECLARE
	reply geometry;
	new_srid INT;
	alaska text[];
	hawaii text[];
	puertorico text[];
BEGIN
	
	alaska = '{"Alaska","AK","02"}'::text[];
	hawaii = '{"Hawaii","HI","15"}'::text[];
	puertorico = '{"Puerto Rico","PR","72"}'::text[];
	
	-- decide on SRID to use
	IF srid = 3857 THEN 
		new_srid = ST_SRID(g);
	ELSE
		new_srid = srid;
	END IF;

	EXECUTE 'SELECT
	    ST_SetSRID(
	    	CASE 
  				WHEN $2 = any($3)
    				THEN
					ST_Scale(
						ST_Translate(
							ST_Transform(
								$1
								, 3338
							)
							, -3800000
							, -900000
						)
						, 0.55
						, 0.55
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
			                    , -4
			                )
			                , 32161
						)
						, 1.5
						, 1.5
					)
				ELSE
					ST_Transform($1,42303)
  				END
  				, $6
  			)'
	INTO reply
	USING g, state, alaska, hawaii, puertorico, new_srid;

	RETURN reply;

END; 
$$ language plpgsql IMMUTABLE;
