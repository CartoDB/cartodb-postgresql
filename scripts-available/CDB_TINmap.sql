CREATE OR REPLACE FUNCTION CDB_TINmap(
    IN geomin geometry[],
    IN colin numeric[],
    IN iterations integer
    )
RETURNS TABLE(geomout geometry, colout numeric)  AS $$
DECLARE
    p geometry[];
    vals numeric[];
    gs geometry[];
    g geometry;
    vertex geometry[];
    centerval numeric;
    va numeric;
    vb numeric;
    vc numeric;
    coltemp numeric[];
BEGIN
    SELECT array_agg(dens.geomout), array_agg(dens.colout) INTO p, vals FROM CDB_Densify(geomin, colin, iterations) dens;
    WITH    a as (SELECT unnest(p) AS e),
            b as (SELECT ST_DelaunayTriangles(ST_Collect(a.e),0.001, 0) AS t FROM a),
            c as (SELECT (ST_Dump(t)).geom AS v FROM b)
        SELECT array_agg(v) INTO gs FROM c;
    FOREACH g IN ARRAY gs
    LOOP
        -- retrieve the vertex of each triangle
        WITH a AS (SELECT (ST_DumpPoints(g)).geom AS v)
            SELECT array_agg(v) INTO vertex FROM a;
        -- retrieve the value of each vertex
        WITH a AS(SELECT unnest(p) as geo, unnest(vals) as c)
            SELECT c INTO va FROM a WHERE ST_Equals(geo, vertex[1]);
        WITH a AS(SELECT unnest(p) as geo, unnest(vals) as c)
            SELECT c INTO vb FROM a WHERE ST_Equals(geo, vertex[2]);
        WITH a AS(SELECT unnest(p) as geo, unnest(vals) as c)
            SELECT c INTO vc FROM a WHERE ST_Equals(geo, vertex[3]);
        -- calc the value at the center
        centerval := (va + vb + vc) / 3;
        -- append the value
        coltemp := array_append(coltemp, centerval);
    END LOOP;
    RETURN QUERY SELECT unnest(gs) as geomout, unnest(coltemp ) as colout;
END;
$$ language plpgsql IMMUTABLE;
