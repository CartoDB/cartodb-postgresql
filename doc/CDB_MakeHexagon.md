Return an Hexagon with given center and side (or maximal radius)

#### Using the function

Running the following SQL

```sql
SELECT CDB_MakeHexagon(ST_MakePoint(0,0),10000000)
```

Would give you back a single hexagon geometry, 

![hexagon](http://i.imgur.com/6jeGStb.png)


#### Arguments

CDB_MakeHexagon(center, radius)

* **center** geometry
* **radius** float. Radius of hexagon measured in same projection as **center**
