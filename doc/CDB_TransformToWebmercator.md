Function to "safely" transform to webmercator. This function is most useful for rendering custom geometries using the CartoDB tiler. Often, transforming a projection like WGS84 can cause issues with extents beyond what are actually valid in webmercator, this attempts to fix those issues.

#### Using the function

Using a box that is nearly the full globe,

```sql
ST_SetSRID(
  ST_Envelope(
    ST_Collect(
      ST_MakePoint(-180,60),
      ST_MakePoint(180,-60)
    )
   ),
   4326
)
```

We can then convert it to a renderable webmercator geometry.

```sql
SELECT CDB_TransformToWebmercator(
 ST_SetSRID(
  ST_Envelope(
    ST_Collect(
      ST_MakePoint(-10,60),
      ST_MakePoint(300,-60)
    )
   ),
   4326
 )
)
```

Would give you back a single valid rectangle in webmercator. Since a longitude of 300 would convert to an unallowed webmercator coordinate, it gets clipped first. Valid extent is WGS84 (-180, -89, 180, 89)

![valid geom](http://i.imgur.com/EFdXiqt.png)


#### Arguments

CDB_TransformToWebmercator(geom)

* **geom** geometry