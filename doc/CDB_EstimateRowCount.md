Estimate the number of rows of a query.


#### Using the function

```sql
SELECT CDB_EstimateRowCount($$
  UPDATE addresses SET the_geom = cdb_geocode_street_point(addr, city, state, 'US');
$$) AS row_count;
```

Result:

```
 row_count
-----------
         5
(1 row)
```

#### Arguments

CDB_EstimateRowCount(query)

* **query** text: the SQL query to estimate the row count for.
