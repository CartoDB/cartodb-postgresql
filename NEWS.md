next (2015-mm-dd)
-----------------

0.10.0 (2015-09-07)
-----------------
* Quote schema and table names returned by CDB_QueryTables [#134](https://github.com/CartoDB/cartodb-postgresql/pull/134). Use quote_ident to quote schema and table names when necessary.
* Fixed CDB_ColumnNames [#122](https://github.com/CartoDB/cartodb-postgresql/issues/122) and CDB_ColumnType [#130](https://github.com/CartoDB/cartodb-postgresql/issues/130) should honor regclass, returning columns for just the table in the schema and not in any other one [#131](https://github.com/CartoDB/cartodb-postgresql/pull/131).
* Add kurtosis and skewness [#124](https://github.com/CartoDB/cartodb-postgresql/pull/124).
* Removed `DROP FUNCTION IF EXISTS cdb_usertables(text);` [#129](https://github.com/CartoDB/cartodb-postgresql/pull/129). This was needed for upgrading between 0.7.4 to 0.8.0 but is no longer needed.

0.9.4 (2015-08-28)
------------------
* Fixed issue with indices when renaming tables [#123](https://github.com/CartoDB/cartodb-postgresql/issues/123)

0.9.3 (2015-08-27)
------------------
* Modify sampling of quota trigger [#126](https://github.com/CartoDB/cartodb-postgresql/issues/126)

0.9.2 (2015-08-24)
------------------
* Fix for `the_geom` column present but not SRID (EWKT) and other corner cases [#121](https://github.com/CartoDB/cartodb-postgresql/pull/121)

0.9.1 (2015-08-19)
------------------
* Fix for transformation to webmercator in corner cases [#116](https://github.com/CartoDB/cartodb-postgresql/issues/116)

0.9.0 (2015-08-19)
------------------
* Re-implementation of `CDB_CartodbfyTable` functions
  - The signature of the main function changes to
    ```
    FUNCTION CDB_CartodbfyTable(destschema TEXT, reloid REGCLASS)
    RETURNS REGCLASS
    ```
    - The `destschema` does not need to match the origin schema of `reloid`
	- It returns the `regclass` of the cartodbfy'ed table, if it needs to be rewritten.
  - There are many optimizations
  - The columns `created_at` and `updated_at` will no longer be added
* Fix for CDB_UserDataSize failing due `ERROR: relation "*" does not exist.` #110
* Review test to validate permissions in public tables [#112](https://github.com/CartoDB/cartodb-postgresql/pull/112)

0.8.3 (2015-08-14)
------------------
* Fixes CDB_UserDataSize failing due `ERROR: relation "*" does not exist.` [#108](https://github.com/CartoDB/cartodb-postgresql/issues/108)

0.8.2 (2015-07-27)
------------------
* Fix for CDB_UserTables returning wrong listings when publicuser is used

0.8.1 (2015-06-30)
------------------
* Fix for [#95](https://github.com/CartoDB/cartodb-postgresql/issues/95) *cdb_usertables should return public tables when the user is publicuser*

0.8.0 (2015-06-30)
------------------
* Adds new function CDB_QueryTablesText that can deal with "schema.table_name"
  longer than 63 chars.
* Adds a set of statistical functions:
  - CDB_DistType
  - CDB_DistinctMeasure
  - CDB_EqualIntervalBins
* Fix for CDB_UserTables returns 0 entries for multiuser accounts [#64](https://github.com/CartoDB/cartodb-postgresql/issues/64)

0.7.4 (2015-06-29)
------------------
Dummy transitional version.

0.7.3 (2015-03-03)
------------------
* Fix upgrade of CDB_StringToDate function
* Add a test for to validate CDB_TableMetadataTouch usage with OID

0.7.2 (2015-03-03)
------------------
* Fix conversion of strings to datetime

0.7.1 (2015-02-27)
------------------
* Revert quota checks to `pg_total_relation_size`

0.7.0 (2015-02-19)
------------------
* Adds CDB_ZoomFromScale function

0.6.0 (2015-02-19)
------------------
* Select permission in CDB_TableMetadata no longer granted to public
* New function to upsert the updated_at in CDB_TableMetadata for a regclass

0.5.3 (2015-02-17)
------------------
* Fixed security problem related with system tables
* Changed quota checks to use `pg_relation_size` instead of `pg_total_relation_size`

0.5.2 (2015-01-29)
------------------
* Improvement: make CDB_UserDataSize functions much faster.

0.5.1 (2014-11-21)
------------------
* Bugfix: Quota check and some organization permissions functions were not properly escaping table name.

0.5.0 (2014-11-03)
------------------
* Support of raster tables for cartodbfication
* Modified quota functions: vector tables stay the same, raster tables count as full size (as have no
  the_geom + the_geom_webmercator combo) and raster overviews are not counted

0.4.1 (2014-09-21)
------------------
* Bugfix for Cartodbfication: Set primary key of the table if not already present (e.g. tables created from SQL API)

0.4.0 (2014-08-27)
------------------
Added CDB_Math_Mode function
Changes in versioning: no revision is attached so it no longer uses `git describe` for the version.

0.3.6 (2014-08-11)
------------------
Dummy release to solve some issues with cdb branch/tag

0.3.5 (2014-08-11)
------------------
Inverting priority of CDB_CheckQuota qmax so gies more priority to existing user quota function over parameter value.

0.3.4 (2014-08-01)
------------------
Fixes issue with schemas in CDB_QueryTables

0.3.3 (2014-07-30)
------------------
* Splitting of CartodbfyTable method in subfunctions to be able to call in fragments and evade timeouts on hot zones

0.3.2 (2014-07-28)
------------------
* Make 0.3.0dev version upgradeable

0.3.1 (2014-07-22)
------------------
* Dummy version. We start using semantic versioning

0.3.0 (2014-07-15)
------------------
* Permission management functions
* Adapt functions to use schemas

0.2.1 - 2014-06-11
------------------

Enhancements:

 - Do not force re-cartodbfication on CREATE FROM unpackaged
 - Drop useless DEFAULT specification in plpgsql variable declarations
 - List plpythonu requirement first, to get pg_catalog scanned before public

Bug fixes:

 - Do not add unique index on cartodb_id if already a primary key (#38)

0.2.0 - 2014-06-09
------------------

Important changes:

 - This release adds dependency on "plpythonu" extension
 - Roles are not created anymore, previously private functions
   for table information extraction (CDB_UserTables, CDB_TableIndexes,
   CDB_ColumnNames, CDB_ColumnType) will now be callable by anyone while
   only returning information about tables over which the calling user
   has SELECT privilege (#36)

Bug fixes:

 - Fix recursive trigger on create table (#32)
 - Ensure cartodb_id uses an associated sequence (#33)
 - Fully qualify call to cdb_disable_ddl_hooks from cdb_enable_ddl_hooks
 - Fully qualify call to CDB_UserDataSize from quota trigger
 - Fully qualify call to CDB_TransformToWebmercator from CDB_CartodbfyTable
 - Fix potential infinite loop in CDB_CartodbfyTable
 - Fix potential infinite loop in CDB_QueryStatements

Enhancements:

 - Include revision info in cdb_version() output (#34)

New features:

 - Add a cdb_extension_reload() function


0.1.0 - 2014-05-23
------------------

Initial release
