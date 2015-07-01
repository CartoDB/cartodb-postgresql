Find the breaks for N categories in a numerical column based on the [Heads/Tails optimization](http://arxiv.org/pdf/1209.2801v1.pdf). Below, Heads/Tails used to color based on the area of the polygons.

![headtails](https://f.cloud.github.com/assets/370259/140655/6eebb918-7228-11e2-89fa-149745f25d34.png)

#### Using the function

We can determine the 7 most optimal breaks in a column of numerical data as follows, 

```sql
SELECT CDB_HeadsTailsBins(array_agg(numeric_column), 7) FROM table_name
-- Results in an ordered array like, {7824,23492,52696,233857,666089,1001709,1638094}
-- Each break happens up to, and equal, to a number: 
-- (bin1 is less than or equal to 7824, bin2 is less than or equal to 23492, etc.)
```

#### Arguments

CDB_HeadsTailsBins(in_array, breaks)

* **in_array** numeric[]. A NUMERIC array of values.
* **breaks** int. The number of categories you want to create