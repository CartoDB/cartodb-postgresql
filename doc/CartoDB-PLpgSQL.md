INTRODUCTION
============

CartoDB uses a number of custom [PLpgSQL](http://www.postgresql.org/docs/8.3/static/plpgsql.html) functions to perform a few magical things. Those functions are accessible to users on CartoDB as well, so we would like to document what they are and what they do here.

## Spatial functions

[CDB_HexagonGrid](CDB_HexagonGrid) - create hexagonal grid from extent and size

[CDB_MakeHexagon](CDB_MakeHexagon) - make a hexagon with given center and side

[CDB_RectangleGrid](CDB_RectangleGrid) - fill given extent with a rectangular coverage

##### Tile based

[CDB_XYZ_Extent](CDB_XYZ_Extent) - Find the extent of a tile by XYZ

[CDB_XYZ_Resolution](CDB_XYZ_Resolution) - Find the pixel resolution of tiles

[CDB_TransformToWebmercator](CDB_TransformToWebmercator) - Convert a geometry to valid webmercator

## Statistical functions

[CDB_JenksBins](CDB_JenksBins) - Find breaks in an array of numbers using Jenks method

[CDB_HeadsTailsBins](CDB_HeadsTailsBins) - Find breaks in an array of numbers using Heads/Tails method

[CDB_QuantileBins](CDB_QuantileBins) - Find quantile breaks in an array of numbers

## System functions

[CDB_UserTables](CDB_UserTables) - Get a list of all tables in your account

[[CDB_SetUserQuotaInBytes]] - Set maximum user quota in bytes

column names - now returned in JSON response

column types - now returned in JSON response
