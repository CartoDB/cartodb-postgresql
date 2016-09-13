List the name of available tables (only the usable ones)

#### Using the function

```sql
--- Returns a row for each table having given permission with the table name.
--- It also returns tables from others users if you've permission to see them. For example, consider the following scenario:
--- User X and User Y at account C.
--- User X has a public table T.
--- User Y will see table T. 
--- Currently accepted permissions are: 'public', 'private' or 'all'
SELECT CDB_UserTables(perms)
```

REF: https://github.com/CartoDB/cartodb-postgresql/blob/master/scripts-available/CDB_UserTables.sql
