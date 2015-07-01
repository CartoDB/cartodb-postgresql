Determine the spatial extent of a tile based on the tile's XYZ coordinate.

#### Using the function

Take a common tile with coordinates x=3, y=2, z=2,

![2/3/2](https://viz2.cartodb.com/tiles/quantile_breaks/2/3/2.png)

To determine its extent you would run,

```sql
SELECT CDB_XYZ_Extent(3,2,2)
--- Returns a WKB polygon in Webmercator (SRID 3857)
```

#### Arguments

CDB_XYZ_Extent(x,y,z)

* **x** integer
* **y** integer
* **z** integer