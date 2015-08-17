Find the breaks for N categories in a numerical column based on the [Jenks optimization](http://en.wikipedia.org/wiki/Jenks_natural_breaks_optimization). Below, Jenks used to color based on the area of the polygons.

![Jenks](https://f.cloud.github.com/assets/370259/140093/b64a9382-7210-11e2-81a4-c65cce3c885e.png)

#### Using the function

We can determine the 7 most optimal breaks in a column of numerical data as follows, 

```sql
SELECT CDB_JenksBins(array_agg(numeric_column), 7) FROM table_name
-- Results in an ordered array like, {0,73,2568,9408,29411,768230,1638094}
-- Each break happens up to, and equal, to a number: 
-- (bin1 is less than or equal to 0, bin2 is less than or equal to 73, etc.)
```

#### Arguments

CDB_JenksBins(in_array, breaks, invert)

* **in_array** numeric[]. A NUMERIC array of values.
* **breaks** int. The number of categories you want to create
* **iterations** OPTIONAL int. The number of iterations used for calculating breaks.
* **invert** OPTIONAL boolean. Flips whether you receive top down breaks or bottom up breaks. Default is top down (so, <=). Bottom up would give you values that define the lower-end start of a bin (so >=).