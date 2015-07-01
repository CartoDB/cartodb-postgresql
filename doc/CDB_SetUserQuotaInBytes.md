Sets user quota in bytes (superuser only)

#### Using the function

```sql
SELECT CDB_SetUserQuotaInBytes(10485760);
--- Returns the previously set quota.
--- Use 0 to disable quota.
```

REF: https://github.com/CartoDB/cartodb-postgresql/blob/master/scripts-available/CDB_Quota.sql
