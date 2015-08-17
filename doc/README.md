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

No user other than the superuser should be allowed to change `statement_timeout` for the session (SET statement_timeout disallowed).

User tables need to match certain structure criteria (See [[CartoDB-user-table]]) so the extension should provide a mean to enforce such structure everytime an attempt to change structure is encountered. 

# Events

The events we want some function to be called upon are:

| event                  | arguments to handler function        | function duty                    | OK* |
|------------------------|--------------------------------------|----------------------------------|-----|
| SET variable           | name of variable                     | forbid changing some vars        |     |
| RENAME table           | old and new name + oid of the table  | flush cache                      |     |
| ADD/DROP/ALTER column  | oid of the table                     | flush cache, cartodbfy, upd meta |  Y  |
| DISABLE/DROP trigger   | oid of table, name of trigger        | cartodbfy or forbid              |     |
| DROP table             | oid of the table                     | flush cache and metadata         |  Y  |
| CREATE table           | oid of the table                     | cartodby, upd metadata           |  Y  |
| GRANT                  | oid of table, privilege, role        | flush cache, upd metadata        |
| REVOKE                 | oid of table, privilege, role        | flush cache, upd metadata        |


* event available by installing https://github.com/CartoDB/pg_schema_triggers

At this stage we don't need more than this, but the number of events and the number of arguments passed to the handler function may expand in the future, so the extension should be written in a way to easily allow that.

Some of the handler will need to act _after_ the statement is completed (CREATE TABLE, for example).

