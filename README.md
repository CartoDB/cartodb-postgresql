cartodb-postgresql
==================

PostgreSQL extension for CartoDB

See https://github.com/CartoDB/cartodb/wiki/CartoDB-PostgreSQL-extension

Dependencies
------------

 * PostgreSQL 9.3+ 
 * [Schema triggers extension]
   (https://bitbucket.org/malloclabs/pg_schema_triggers)

Install
-------

 make all install

Test installation
-----------------

 make installcheck

NOTE: if ``test_ddl_triggers`` fails it's likely due to an incomplete
      installation of schema_triggers: you need to add ``schema_triggers.so``
      to the ``shared_preload_libraries`` setting in postgresql.conf !

Usage
-----

In a database that needs to beturned into a "cartodb" user database, run:

```sql
  CREATE EXTENSION postgis;
  CREATE EXTENSION schema_triggers;
  CREATE EXTENSION cartodb;
```

