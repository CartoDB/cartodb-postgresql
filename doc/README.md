# Contents

* [CartoDB-user-table](CartoDB-user-table.md)
* [CartoDB-PLpgSQL](CartoDB-PLpgSQL.md)
* [CDB_ColumnNames](CDB_ColumnNames.md)
* [CDB_ColumnType](CDB_ColumnType.md)
* [CDB_HeadsTailsBins](CDB_HeadsTailsBins.md)
* [CDB_HexagonGrid](CDB_HexagonGrid.md)
* [CDB_JenksBins](CDB_JenksBins.md)
* [CDB_MakeHexagon](CDB_MakeHexagon.md)
* [CDB_QuantileBins](CDB_QuantileBins.md)
* [CDB_RectangleGrid](CDB_RectangleGrid.md)
* [CDB_SetUserQuotaInBytes](CDB_SetUserQuotaInBytes.md)
* [CDB_TransformToWebmercator](CDB_TransformToWebmercator.md)
* [CDB_UserTables](CDB_UserTables.md)
* [CDB_XYZ_Extent](CDB_XYZ_Extent.md)
* [CDB_XYZ_Resolution](CDB_XYZ_Resolution.md)

The CartoDB PostgreSQL extension is a module to load into each CartoDB user database to perform cartodb-specific security and functionality checks.

# Checks

User tables need to match certain structure criteria (See [[CartoDB-user-table]]) so the extension should provide a mean to enforce such structure everytime an attempt to change structure is encountered. 
