cartodb-postgresql
==================

[![Build Status](http://api.travis-ci.org/CartoDB/cartodb-postgresql.svg?branch=master)](http://travis-ci.org/CartoDB/cartodb-postgresql)

PostgreSQL extension for CartoDB

See [the cartodb-postgresql wiki](https://github.com/CartoDB/cartodb-postgresql/wiki).

Dependencies
------------

 * PostgreSQL 9.6+ (with plpythonu extension and xml support)
 * [PostGIS extension](http://postgis.net)
 * Python with [Redis module](https://pypi.org/project/redis/)

Install
-------

```sh
make all install
```

Test installation
-----------------

```sh
make installcheck
```

NOTE: you need to run the installcheck as a superuser, use PGUSER
      env variable if needed, like: PGUSER=postgres make installcheck
      
NOTE: the tests need to run against a **clean postgres instance**, if you have some roles already created test will likely fail due `publicuser` not being dropped.

Enable database
---------------

In a database that needs to be turned into a "cartodb" user database, run:

```sql
CREATE EXTENSION postgis;
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
CREATE EXTENSION cartodb FROM unpackaged;
```

Update cartodb extension
------------------------

Updating the version of cartodb extension installed in a database
is done using ALTER EXTENSION.

```sql
ALTER EXTENSION cartodb UPDATE TO '0.1.1';
```

The target version needs to be installed on the system first
(see Install section).

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
every commit, so testing latest change requires special steps documented
in the CONTRIBUTING document, under "Testing changes live".

Limitations
-----------

- The main schema of an organization user must have one only owner (the user).
