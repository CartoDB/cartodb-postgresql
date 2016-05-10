Overviews are tables that represent a *reduced* version of a dataset intended
for efficient rendering at certain zoom levels while preserving the
general visual appearance of the complete dataset.

The *reduction* consists in havig a fewer number of records
(while each overview record may represent an aggregation of multiple records)
and/or simplified record geometries.

Overviews are created through the `CDB_CreateOverviews` function.
The statement timeout may need to be adjusted before using this function,
as overview creation for large tables is a time-consuming operation.

The `CDB_Overviews` function can be used determine what overview tables
exist for a given dataset table and which zoom levels correspond to it.

The `CDB_DropOverviews` function removes a dataset's existing overviews.

To know if overview tables exist for some base table, and to obtain
a list of which overview tables are approrpiate for which zoom levels,
the `CDB_Overviews` functions can be used.

The zoom level we're referring here to are those used
by the tiler: http://wiki.openstreetmap.org/wiki/Zoom_levels

### CDB_CreateOverviews

Create overviews for vector dataset.

#### Using the function

The table for which overviews will be generated should be
a Cartodbfied dataset with vector geometry.

```sql
SELECT CDB_CreateOverviews('table_name');
--- Generates overview tables for the dataset
```

#### Arguments

CDB_CreateOverviews(table_name, ref_z_strategy, reduction_strategy)

* **table_name** regclass, table for which overviews will be generated
* **ref_z_strategy** regproc, optional function that provides
  the Z-scale strategy.
  It returns the base Z level for the dataset.
  It should have these arguments:
  - **table_name** regclass, table to compute the reference Z scale for
* **reduction_strategy** regproc, optional function that provides
  the reduction strategy to generate an overview table from a table
  for a smaller scale (higher Z number).
  It returns the name of the generated table.
  It should have these arguments:
  - **base_table_name** regclass, base table to be reduced.
  - **base_z** integer, base Z level assigned to the base table.
  - **overview_z** integer, Z level for which to generate the overview.

#### Tolerance / level of detail

The level of detail to be representable by each overview layer can
be specified as a tolerance in pixels (if different from the default of 1 pixel)
with the function `CDB_CreateOverviewsWithToleranceInPixels`
which has as a second additional argument the desired tolerance.

This tolerance defines the maximum deviation in pixels of the overviews
geometries with respect to the original geometries when overview tables
are used for their intendend zoom level.

### CDB_Overviews

Obtain overview metadata for a given table (existing overviews).
The returned relation will be empty if the table has no overviews.

The function can be applied to a single table:

```sql
SELECT CDB_Overviews('table_name');
--- Return existing overview Z levels and corresponding tables
```

Or to multiple tables passed as an array; this can be used
to obtain the overviews that can be applied to a query by
combining it with `CDB_QueryTablesText`:

```sql
SELECT CDB_Overviews(CDB_QueryTablesText('SELECT * FROM table1, table2'));
--- Return existing overview Z levels and corresponding tables
```

The result of `CDB_Overviews` has three columns:

| base_table | z | overview_table |
| ---------- | - | -------------- |
| table1     | 1 | table1_ov1     |
| table1     | 2 | table1_ov2     |
| table1     | 4 | table1_ov4     |
| table2     | 1 | table1_ov1     |
| table2     | 2 | table1_ov2     |

#### Arguments

CDB_Overviews(table_name)

* **table_name** regclass, oid of table to obtain existing overviews for

CDB_Overviews(table_names)

* **table_names** regclass[], array of table oids


### CDB_DropOverviews

Remove the overviews of a table, if present.

```sql
SELECT CDB_DropOverviews('table_name');
```

#### Arguments

CDB_Overviews(table_name)

* **table_name** regclass, table for which to drop existing overviews.
