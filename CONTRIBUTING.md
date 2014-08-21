The development tracker for cartodb-postgresql is on github:
http://github.com/cartodb/cartodb-postgresql/

Bug fixes are best reported as pull requests over there.
Features are best discussed on the mailing list:
https://groups.google.com/d/forum/cartodb

Adding features to the extension
--------------------------------

Extension features are coded in scripts found under the
"scripts-available" directory. A feature can be a single function
or a group of function with a specific scope.

The "scripts-enabled" directory contains symlinks to the scripts
in "scripts-available". Any symlink in that directory is automatically
included in the extension. Numbering can be used to enforce the order
in which those scripts are loaded.

Scripts would be best coded in a way to be usable both for creation
and upgrade of the objects. This means using CREATE OR REPLACE for
the functions, and whatever it takes to check existence of any previous
version of objects in other cases.

When used as an extension (probably always from version 0.2.0 onwards)
all the objects will be installed in a "cartodb" schema. Take this into
account to fully-qualify internal calls to avoid (possibly dangerous)
name clashes.

Every new feature (as well as bugfixes) should come with a test case,
see next section.

Writing testcases
-----------------

Tests reside in the test/ directory.
You can find information about how to write tests in test/README

Testing changes live
--------------------

Testing changes made during development requires upgrading
the extension into your test database. 

During development the cartodb extension version doesn't change with
every commit, so testing latest change requires cheating with PostgreSQL
so to enforce re-load of the scripts. To help with cheating, "make install"
also installs migration scripts to go from "V" to "V"next and from "V"next
to "V". Example to upgrade a 0.2.0dev version:

```sql
ALTER EXTENSION cartodb UPDATE TO '0.2.0devnext';
ALTER EXTENSION cartodb UPDATE TO '0.2.0dev';
```

Starting with 0.2.0, the in-place reload can be done with an ad-hoc function:

```sql
SELECT cartodb.cdb_extension_reload();
```
