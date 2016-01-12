Overviews are tables that represent a *reduced* version of a dataset intended
for efficient rendering at certain zoom levels while preserving the
general visual appearance of the complete dataset.

The *reduction* consists in a fewer number of records
(while each overview record may represent an aggregation of multiple records)
and/or simplified record geometries.

Overviews are created through the `CDB_CreateOverviews`.
The statement timeout may need to be adjusted before using this function,
as overview creation for large tables is a time-consuming operation.

The `CDB_Overviews` function can be used determine what overview tables
exist for a given dataset table and which zoom levels correspond to it.

The `CDB_DropOverviews` remove a dataset's existing overviews.

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

### CDB_Overviews

Obtain overview metadata for a given table (existing overviews).
The returned relation will be empty if the table has no overviews.

```sql
SELECT CDB_Overviews('table_name');
--- Return existing overview Z levels and corresponding tables
```

#### Arguments

CDB_Overviews(table_name)

* **table_name** regclass, table to obtain existing overviews for

### CDB_DropOverviews

Remove the overviews of a table, if present.

```sql
SELECT CDB_DropOverviews('table_name');
```

#### Arguments

CDB_Overviews(table_name)

* **table_name** regclass, table for which to drop existing overviews.
