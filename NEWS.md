0.31.0 (2019-10-08)
* Ghost tables: Add missing tags (#370)
* Set search_path in security definer functions.

0.30.0 (2019-07-17)
* Added new admin functions to connect CARTO with user FDW's (#369)

0.29.0 (2019-07-15)
* Added new function CDB_OAuth:
  * Install event trigger to check for table/view/sequence/function creation
  * Reassign the ownership of new objects to a defined role in the cdb_conf
* Changed MakeFile to support different expects for differents PG versions

0.28.1 (2019-07-04)
* Avoid temporary tables creation in CDB_SyncTable (#366)
* Make CDB_Get_Foreign_Updated_At robust to missing CDB_TableMetadata (#362)

0.28.0 (2019-07-01)
* New function CDB_SyncTable (#355)

0.27.2 (2019-06-21)
* Improvements and fixes in Ghost tables functions (#360)

0.27.1 (2019-06-03)
* Add some qualifications that were left in the previous release.

0.27.0 (2019-06-03)
* Fully qualify function calls
* Several improvements to bash tests.
* Avoid dropping publicuser in tests.
* Raise minimum requirement to PostgreSQL 9.6.

0.26.1 (2019-03-19)
* Remove default TIS values from Ghost tables functions

0.26.0 (2019-03-11)
* Use `ST_ShiftLongitude` instead of `ST_Shift_Longitude`.
* Add Ghost tables functions to install triggers and enqueue the linking process

0.25.0 (2019-02-22)
* Add `CDB_Username` to get the cartodb username from the current PostgreSQL user

0.24.1 (2019-01-02)
* Drop functions removed in 0.12 (#341)
* Travis: Test with PostgreSQL 9.5, 10 and 11.

0.24.0 (2018-09-13)
* Travis: Test with PostgreSQL 9.5 and 10.
* _cdb_estimated_extent: Fix bug with ST_EstimatedExtent interaction.
* Improvements in `CDB_JenksBins`.
  * Now it ignores NULLs.
  * No longer puts the same value in multiple categories.
  * Removes all limits related to size.
  * If not set, the number of iterations done is based now on the size of the array.
  * Fixed multiple bugs.
  * The internal function `CDB_JenksBinsIteration` has changed its signature.

0.23.2 (2018-07-19)
* Fix `CDB_QueryTablesText` with parenthesized queries (#335)

0.23.1 (2018-07-19)
* Fix `CDB_EstimateRowCount` parallelizability #333

0.23.0 (2018-07-03)
* Add a new helper function `_CDB_Table_Exists(table_name_with_optional_schema TEXT)` #332

0.22.2 (2018-05-29)
* Fix: Fix hyphenates usernames in 0.22.1 fix (#331)

0.22.1 (2018-05-29)
* Fix: Correctly grant permission to all sequences related with table (#330)

0.22.0 (2018-03-22)
* Fix: allow older ogr2ogr to work in -append mode (#319,#325)
* Refactors CDB_QuantileBins to rely on PostgreSQL function `percentile_disc` #316

0.21.0 (2018-02-15)
* Add optional parameter to limit the number of cells in grid-generation functions #322
* Fix: grant usage on cartodb_id sequence when sharing read write #323
* Fix: Change sed in-place for tmpfiles 524319

0.20.0 (2017-11-08)
* Added VOLATILITY and PARALLEL categories to all functions

0.19.2 (2017-06-30)
* Improved functions to generate unique identifiers #305

0.19.1 (2017-06-05)

* Fixed a deadlock problem when trying to regenarate overviews #302

0.19.0 (2017-04-11)

* Add new function `CDB_EstimateRowCount` #295

0.18.5 (2016-11-30)

* Add to new overview creation strategies #290
* Fix tests: race condition with publicuser #157
* Fix: CDB_Stats divisions by zero #181
* Better implementation of `CDB_EqualIntervalBins` #244
* New tests for binning functions #249

0.18.4 (2016-11-04)

* No functional changes; fixes the migration from previous versions #288

0.18.3 (2016-11-03)

* Exclude analysis cache tables from the quota #281

0.18.2 (2016-10-20)
-------------------

* Fix: cleanup inconsistent position of `username` column in analysis catalog after upgrades
  [#285](https://github.com/cartodb/cartodb-postgresql/pull/285)

0.18.1 (2016-10-19)
-------------------

* Increase analysis limit factor to 2 [#284](https://github.com/CartoDB/cartodb-postgresql/pull/284)

0.18.0 (2016-10-17)
-------------------

* Fix: exclude NULL geometries when creating Overviews #269
* Function to check analysis tables limits #279

0.17.1 (2016-08-16)
-------------------

* Add cache_tables column to cdb_analysis_catalog table #274.


0.17.0 (2016-07-04)
-------------------

* Add export config for cdb_analysis_catalog table #268.
* Add some extra fields to cdb_analysis_catalog table. Track user, error_message for failures, and last entity modifying the node #267.
* Exclude overviews from user data size #262.


0.16.4 (2016-05-27)
-------------------

* Change CDB_ZoomFromScale() to use a formula and raise
  maximum overview level from 23 to 29.
  [#259](https://github.com/CartoDB/cartodb-postgresql/pull/259)

* Fix bug in overview creating causing it to fail when `x` or
  `y` columns exist with non-integer type. Prevent also
  potential integer overflows limiting maximum overview level
  to 23.
  [#258](https://github.com/CartoDB/cartodb-postgresql/pull/258)


0.16.3 (2016-05-09)
-------------------

* Fix overview creation problem for organization users
  with names that require quoting:
  [#253](https://github.com/CartoDB/cartodb-postgresql/pull/253)

0.16.2 (2016-04-27)
-------------------

* Use the mode to aggregate category columns in overviews
  [#246](https://github.com/CartoDB/cartodb-postgresql/pull/246)

0.16.1 (2016-04-25)
-------------------

* Optimize column information functions performance
  [#238](https://github.com/CartoDB/cartodb-postgresql/pull/238)

* Adjust overview points to pixel CDB_EqualIntervalBins
  [#242](https://github.com/CartoDB/cartodb-postgresql/pull/242)

* Compute webmercator resolution using full numeric precision
  [#243](https://github.com/CartoDB/cartodb-postgresql/pull/243)


0.16.0 (2016-04-15)
-------------------
* Adds table for storing camshaft analysis nodes
  [#237](https://github.com/CartoDB/cartodb-postgresql/pull/237)

0.15.1 (2016-04-15)
-------------------
* Fix problems with org users in overviews functions
  [#224](https://github.com/CartoDB/cartodb-postgresql/pull/224)
* Add `_feature_count` to overviews
  [#227](https://github.com/CartoDB/cartodb-postgresql/pull/227)
* Change point clustering behaviour of overviews
  [#228](https://github.com/CartoDB/cartodb-postgresql/pull/228)
* Change default tolerance of overviews
  [#230](https://github.com/CartoDB/cartodb-postgresql/pull/230)
* Fix problem with aggregated numerical fields in overviews
  [#233](https://github.com/CartoDB/cartodb-postgresql/pull/233)
* Enhance aggregation of text fields in overviews
  [#234]https://github.com/CartoDB/cartodb-postgresql/pull/234

0.15.0 (2016-04-05)
-------------------
* New function CDB_CreateOverviewsWithToleranceInPixels that adds tolerance parameter for overview creation
  [#221](https://github.com/CartoDB/cartodb-postgresql/pull/221)
* New default value for the overviews tolerance in pixels is 2 (used to be 7.5) (also in #221)
* The feature density limit used to choose the reference Z level now depends on the tolerance in pixels (also in #221)
* Tables that require an explicit schema can now be passed to overview functions
  [#220](https://github.com/CartoDB/cartodb-postgresql/pull/220)

0.14.4 (2016-03-29)
-------------------
* Fix creating overviews for tables with boolean columns
  [#214](https://github.com/CartoDB/cartodb-postgresql/pull/214)
* Fix tests for some systems [#215](https://github.com/CartoDB/cartodb-postgresql/pull/215)

0.14.3 (2016-03-17)
-------------------
* Fix for `cartodb_id` bigint casting hardcoded in 0.14.2 to support `cartodb_id` text columns [#210](https://github.com/CartoDB/cartodb-postgresql/pull/210)

0.14.2 (2016-03-15)
-------------------
* Support text `cartodb_id` columns in `_CDB_Has_Usable_Primary_ID` [#202](https://github.com/CartoDB/cartodb-postgresql/pull/202)

0.14.1 (2016-03-07)
-------------------
* Fully qualify table names in cache cdb_invalidate_varnish calls [#198](https://github.com/CartoDB/cartodb-postgresql/issues/198)

0.14.0 (2016-02-14)
-------------------
* Add CDB_ForeignTable.sql to support FDW's [#199](https://github.com/CartoDB/cartodb-postgresql/pull/199)

0.13.1 (2016-02-01)
-------------------
* Fix migration fron unpackaged. [193](https://github.com/CartoDB/cartodb-postgresql/pull/193)

0.13.0 (2016-01-29)
-------------------
* Add CDB_CreateOverviews, CDB_DropOverviews and CDB_Overviews for vector overviews support. [185](https://github.com/CartoDB/cartodb-postgresql/pull/185)
* Convert some simple functions from plpgsql to sql. [188](https://github.com/CartoDB/cartodb-postgresql/pull/188)

0.12.0 (2016-01-27)
-------------------
* Remove schema_triggers extension dependency, to ensure compatibility with PostgreSQL 9.5. [#190](https://github.com/CartoDB/cartodb-postgresql/pull/190)
* Remove DDL trigger functions (unused by CartoDB).

0.11.5 (2015-11-27)
-------------------
* Disable log invalidation time [#178](https://github.com/CartoDB/cartodb-postgresql/pull/178)

0.11.4 (2015-11-24)
-------------------
* Fix for existing PK cartodb_id problem [#174](https://github.com/CartoDB/cartodb-postgresql/issues/174)
* Add cartodbfication support for column names with embedded points to fix [#6114](https://github.com/CartoDB/cartodb/issues/6114)
* Add CDB_GreatCircle for creating great circle routes between two points [#171](https://github.com/CartoDB/cartodb-postgresql/pull/171)
* Fix to prevent cartodbfication problems [#155](https://github.com/CartoDB/cartodb-postgresql/issues/155)

0.11.3 (2015-10-27)
-------------------
* Added CDB_Helper.sql [#173](https://github.com/CartoDB/cartodb-postgresql/pull/173)
* Added `_CDB_Unique_Identifier` for creating UTF8 aware unique identifiers
* Added `_CDB_Unique_Column_Identifier` for creating UTF8 aware unique identifiers for columns
* Added `_CDB_Octet_Truncate` that truncates text to a certain amount of octets.

0.11.2 (2015-10-19)
-------------------
* Fix schema not being specified on pg_get_serial_sequence [#170](https://github.com/CartoDB/cartodb-postgresql/pull/170)
* Log invalidation function call duration in seconds [#163](https://github.com/CartoDB/cartodb-postgresql/pull/163)

0.11.1 (2015-10-06)
-------------------
* Added CDB_DateToNumber(timestamp with time zone) [#169](https://github.com/CartoDB/cartodb-postgresql/pull/169)
* cartodbfy now discards cartodb_id candidates that contain nulls [#148](https://github.com/CartoDB/cartodb-postgresql/issues/148)

0.11.0 (2015-09-dd)
-------------------
* Groups API

0.10.2 (2015-09-24)
-------------------
* Add back the `DROP FUNCTION IF EXISTS CDB_UserTables(text);` to be able to upgrade from `0.7.3` upward [#160](https://github.com/CartoDB/cartodb-postgresql/issues/160)

0.10.1 (2015-09-16)
-------------------
* Get back the `update_updated_at` function (still used by old tables) [#143](https://github.com/CartoDB/cartodb-postgresql/pull/143)
* Fix for CDB_StatsTest.sql test failing randomly [#144](https://github.com/CartoDB/cartodb-postgresql/issues/144)
* Fix for table cartodbfy'ed without default seq value [#138](https://github.com/CartoDB/cartodb-postgresql/issues/138)
* Fix for cartodbfy error column `the_geom` already exists [#141](https://github.com/CartoDB/cartodb-postgresql/issues/141)
* Fix for columns with geometry cartodbfy'ed without SRID [#154](https://github.com/CartoDB/cartodb-postgresql/issues/154)

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
