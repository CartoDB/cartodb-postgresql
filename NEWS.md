0.5.3 (2015-02-xx)
------------------
* Fixed secuity problem related with system tables
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
