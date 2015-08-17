Fill given extent with an hexagonal coverage

#### Using the function

Create a hexagonal grid from a polygon geometry. For example, take the geometry

```sql
  ST_SetSRID(
    ST_Envelope(
      ST_Collect(
        ST_MakePoint(10000000,-10000000),
        ST_MakePoint(-10000000,10000000)
      )
     ),
     3857)
```

We can create a grid as follows, 

```sql
SELECT CDB_HexagonGrid(
  ST_SetSRID(
    ST_Envelope(
      ST_Collect(
        ST_MakePoint(10000000,-10000000),
        ST_MakePoint(-10000000,10000000)
      )
     ),
     3857),
   1000000) the_geom_webmercator
```

Which will look something like this,

![grid tile](http://i.imgur.com/4rZXGMb.png)

#### Arguments

CDB_HexagonGrid(ext, side, origin)

* **ext** geometry. Extent to fill. Only hexagons with center point falling inside the extent (or at the lower or leftmost edge) will be emitted. The returned hexagons will have the same SRID as this extent.
* **side** float. Side measure for the hexagon. Maximum diameter will be 2 * side. Measure is in the same projection as **ext**
* **origin** OPTIONAL geometry. Optional origin to allow for exact tiling. If omitted the origin will be 0,0. The parameter is checked for having the same SRID as the extent.