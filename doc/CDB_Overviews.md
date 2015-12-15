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
* **ref_z_strategy** regproc, function that provides the Z-scale strategy.
  It returns the base Z level for the dataset.
  It should have these arguments:
  - **table_name** regclass, table to compute the reference Z scale for
* **reduction_strategy** regproc, function that provides the reduction strategy
  to generate an overview table from a table for a smaller scale (higher Z number).
  It returns the name of the generated table.
  It should have these arguments:
  - **base_table_name** regclass, base table to be reduced.
  - **base_z** integer, base Z level assigned to the base table.
  - **overview_z** integer, Z level for which to generate the overview.
