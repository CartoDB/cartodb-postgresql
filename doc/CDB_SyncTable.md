Synchronize two tables. This function will synchronize a *destination* table with a *source* table.
The idea is that the *destination* is a replica of *source* and *source* has been subject to
modifications that are to be applied to *destination*.

This will be achieved by deleting the rows in the destination not present
in the source, inserting rows of the source not in the destination and updating modified rows.
If the destination table does not exist it will be created and all the rows of the source inserted into it.

Both tables must have a consistent `cartodb_id` primary key column which will be used to match
the source and destination rows.

Note that both tables do not necessarily become identical after the synchronization, since additional columns
may have been added to the destination; those columns will not be altered by the synchronization.

In addition some source columns may be skipped by listing them in the optional last argument; such columns
will not be updated in the destination, so if they are present in it their values won't be altered.


#### Using the function

Import some data using COPY FROM into a temporary table, then synchronize a table with the data and
finally delete the temporary table. This could be used import and update some data periodically while
allowing to add columns to the data that will be preserved across updates.

```sql
CREATE tmp_pois(cartodb_id int, name text, type text, longitude double precision, latitude double precision, rank int);
COPY tmp_pois FROM '/tmp/pois.csv';
SELECT CDB_SyncTable('tmp_pois', 'public', 'pois');
DROP TABLE tmp_pois;
```

Now we could perform some changes to the `pois` to maintain our own ranking:

```sql
UPDATE pois SET rank = random()*4 + 1;
```

Then, if the source were updated at `/tmp/pois.csv` we could synchronize with it while preserving our `rank` values with:

```sql
CREATE tmp_pois(cartodb_id int, name text, type text, longitude double precision, latitude double precision, rank int);
COPY tmp_pois FROM '/tmp/pois.csv';
SELECT CDB_SyncTable('tmp_pois', 'public', 'pois', '{rank}');
DROP TABLE tmp_pois;
```

#### Arguments

```
CDB_SyncTable(src_table, dst_schema, dst_table, skip_cols)
```

* **src_table** REGCLASS the source data for the synchronization
* **dst_scgena** REGNAMESPACE the destination schema
* **dst_table** NAME the destination table to be updated
* **skip_cols** NAME[] an array of column names, empty by default, which will be skipped
