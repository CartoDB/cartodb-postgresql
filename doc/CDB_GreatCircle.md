Based on Paul Ramsey's [blog post](http://blog.cartodb.com/jets-and-datelines/).
#### Using the function

Creates a great circle line.

```sql
SELECT CDB_GreatCircle(start_point, end_point) FROM table_name
-- Results a line reprsenting the great circle between the two points
```

#### Arguments

CDB_GreatCircle(start_point, end_point)

* **start_point** ST_Point indicating the start of the line.
* **end_point** ST_point indicating the end of the line.
