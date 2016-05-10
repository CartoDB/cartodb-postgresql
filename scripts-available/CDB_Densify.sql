--
-- Iterative densification of a set of points using Delaunay triangulation
-- the new points have as assigned value the average value of the 3 vertex (centroid)
--
-- @param geomin - array of geometries (points)
--
-- @param colin - array of numeric values in that points
--
-- @param iterations - integer, number of iterations
--
--
-- Returns: TABLE(geomout geometry, colout numeric)
--
--
CREATE OR REPLACE FUNCTION CDB_Densify(
    IN geomin geometry[],
    IN colin numeric[],
    IN iterations integer
    )
RETURNS TABLE(geomout geometry, colout numeric)  AS $$
DECLARE
    geotemp geometry[];
    coltemp numeric[];
    i integer;
    gs geometry[];
    g geometry;
    vertex geometry[];
    va numeric;
    vb numeric;
    vc numeric;
    center geometry;
    centerval numeric;
    tmp integer;
BEGIN
    geotemp := geomin;
    coltemp := colin;
    FOR i IN 1..iterations
    LOOP
        -- generate TIN
        WITH    a as (SELECT unnest(geotemp) AS e),
                b as (SELECT ST_DelaunayTriangles(ST_Collect(a.e),0.001, 0) AS t FROM a),
                c as (SELECT (ST_Dump(t)).geom AS v FROM b)
        SELECT array_agg(v) INTO gs FROM c;
        -- loop cells
        FOREACH g IN ARRAY gs
        LOOP
            -- append centroid
            SELECT ST_Centroid(g) INTO center;
            geotemp := array_append(geotemp, center);
            -- retrieve the value of each vertex
            WITH a AS (SELECT (ST_DumpPoints(g)).geom AS v)
            SELECT array_agg(v) INTO vertex FROM a;
            WITH a AS(SELECT unnest(geotemp) as geo, unnest(coltemp) as c)
            SELECT c INTO va FROM a WHERE ST_Equals(geo, vertex[1]);
            WITH a AS(SELECT unnest(geotemp) as geo, unnest(coltemp) as c)
            SELECT c INTO vb FROM a WHERE ST_Equals(geo, vertex[2]);
            WITH a AS(SELECT unnest(geotemp) as geo, unnest(coltemp) as c)
            SELECT c INTO vc FROM a WHERE ST_Equals(geo, vertex[3]);
            -- calc the value at the center
            centerval := (va + vb + vc) / 3;
            -- append the value
            coltemp := array_append(coltemp, centerval);
        END LOOP;
    END LOOP;
    RETURN QUERY SELECT unnest(geotemp ) as geomout, unnest(coltemp ) as colout;
END;
$$ language plpgsql IMMUTABLE;
