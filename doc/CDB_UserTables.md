List the name of available tables (only the usable ones)

#### Using the function

```sql
--- Returns a row for each table having given permission with the table name
--- Currently accepted permissions are: 'public', 'private' or 'all'
SELECT CDB_UserTables(perms)
```

REF: https://github.com/CartoDB/cartodb-postgresql/blob/master/scripts-available/CDB_UserTables.sql
