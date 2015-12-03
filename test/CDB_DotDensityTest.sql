WITH g AS (
  SELECT ST_Buffer(
    CDB_LatLng(0,0)::geometry, 1000)::geometry AS g
),
points AS(
  SELECT (
    ST_Dump(
      CDB_DotDensity(g.g, 100)
    )
  ).geom AS p FROM g
)

SELECT count(*), sum(CASE WHEN ST_Contains(g,p) THEN 1 ELSE 0 END) FROM points, g
