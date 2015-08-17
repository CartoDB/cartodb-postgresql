Return pixel resolution of tiles at a given zoom level

#### Using the function

Take a common tile with zoom, z=2,

![2/3/2](https://viz2.cartodb.com/tiles/quantile_breaks/2/3/2.png)

To determine the resolution of these pixels,

```sql
SELECT CDB_XYZ_Resolution(2)
--- Returns a float, 39135.7587890625
```

#### Arguments

CDB_XYZ_Resolution(z)

* **z** integer