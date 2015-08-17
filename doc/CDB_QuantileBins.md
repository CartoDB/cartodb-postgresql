Find the breaks for N categories in a numerical column based on the [Quantile bins]. Below, the quantile method is used to determine color based on the area of the polygons.

![qunatile](https://f.cloud.github.com/assets/370259/140714/932ed0e6-722b-11e2-9807-ffbd0fddb9ac.png)

#### Using the function

We can determine the 7 most optimal breaks in a column of numerical data as follows, 

```sql
SELECT CDB_QuantileBins(array_agg(numeric_column), 7) FROM table_name
-- Results in an ordered array like, {80,2281,7162,17652,39730,91077,1638094}
-- Each break happens up to, and equal, to a number: 
-- (bin1 is less than or equal to 80, bin2 is less than or equal to 2281, etc.)
```

#### Arguments

CDB_QuantileBins(in_array, breaks)

* **in_array** numeric[]. A NUMERIC array of values.
* **breaks** int. The number of categories you want to create