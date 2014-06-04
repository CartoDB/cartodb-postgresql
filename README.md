cartodb-postgresql
==================

[![Build Status](http://travis-ci.org/CartoDB/cartodb-postgresql.png)]
(http://travis-ci.org/CartoDB/cartodb-postgresql)

PostgreSQL extension for CartoDB

See https://github.com/CartoDB/cartodb/wiki/CartoDB-PostgreSQL-extension

Dependencies
------------

 * PostgreSQL 9.3+ 
 * [Schema triggers extension]
   (https://bitbucket.org/malloclabs/pg_schema_triggers)
   (or [fork](https://github.com/CartoDB/pg_schema_triggers))

Install
-------

 make all install

Test installation
-----------------

 make installcheck

NOTE: if ``test_ddl_triggers`` fails it's likely due to an incomplete
      installation of schema_triggers: you need to add ``schema_triggers.so``
      to the ``shared_preload_libraries`` setting in postgresql.conf !

Enable database
---------------

In a database that needs to be turned into a "cartodb" user database, run:

```sql
CREATE EXTENSION postgis;
CREATE EXTENSION schema_triggers;
CREATE EXTENSION cartodb;
```

Migrate existing cartodb database
---------------------------------

When upgrading an existing cartodb user database, the cartodb extension
can be migrated from the "unpackaged" version. The procedure will copy
the data from ``public.CDB_TableMetada`` to ``cartodb.CDB_TableMetadata``,
re-cartodbfy all tables using old functions in triggers and drop the
cartodb functions from the 'public' schema. All new cartodb objects will
be in the "cartodb" schema.

```sql
CREATE EXTENSION postgis FROM unpackaged;
CREATE EXTENSION schema_triggers;
CREATE EXTENSION cartodb FROM unpackaged;
```

Update cartodb extension
------------------------

Updating the version of cartodb extension installed in a database
is done using ALTER EXTENSION.

```sql
ALTER EXTENSION cartodb UPDATE TO '0.1.1';
```

If the "TO 'x.y.z'" part is omitted, the extension will be updated to the
latest installed version, which you can find with the following command:

```sh
grep default_version `pg_config --sharedir`/extension/cartodb.control
```

Updates are performed by PostgreSQL by loading one or more migration scripts
as needed to go from the installed version S to the target version T.
All migration scripts are in the "extension" directory of PostgreSQL:

```sh
ls `pg_config --sharedir`/extension/cartodb*
```

During development the cartodb extension version doesn't change with
every commit, so testing latest change requires cheating with PostgreSQL
so to enforce re-load of the scripts. To help with cheating, "make install"
also installs migration scripts to go from "V" to "V"next and from "V"next
to "V". Example to upgrade a 0.2.0dev version:

```sql
ALTER EXTENSION cartodb UPDATE TO '0.2.0devnext';
ALTER EXTENSION cartodb UPDATE TO '0.2.0dev';
```
